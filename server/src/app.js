'use strict';
// Express app. `db` is a Supabase client (service role) so tests can inject a fake.

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const ROLES = ['superadmin', 'admin', 'viewer'];
const TIME_RE = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?/;

function wrap(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

function check({ error }, what) {
  if (error) throw httpError(500, `${what}: ${error.message}`);
}

const publicAdmin = (a) => ({
  id: a.id,
  email: a.email,
  name: a.name,
  role: a.role,
  disabled: !!a.disabled,
});

const toIso = (v) => (v ? new Date(v).toISOString() : new Date().toISOString());
const normTime = (t) => String(t).replace('T', ' ').slice(0, 19).padEnd(19, ':00').slice(0, 19);

// ------------------------------------------------------------ mappers
const studentOut = (r) => ({
  id: r.id, name: r.name, section: r.section, authority: r.authority,
  lrn: r.lrn, contact: r.contact, notes: r.notes, schedule: r.schedule,
  updatedAt: r.updated_at, deleted: r.deleted,
});
const sectionOut = (r) => ({ no: r.no, name: r.name, week: r.week, updatedAt: r.updated_at });
const shiftOut = (r) => ({
  no: r.no, in1: r.in1, out1: r.out1, in2: r.in2, out2: r.out2,
  otIn: r.ot_in, otOut: r.ot_out, updatedAt: r.updated_at,
});
const rulesOut = (r) => ({
  company: r.company, lateAllow: r.late_allow, earlyAllow: r.early_allow,
  repeatMin: r.repeat_min, scheduleMode: r.schedule_mode, updatedAt: r.updated_at,
});

function createApp({ db, jwtSecret, corsOrigin }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // Render sits behind a proxy
  app.use(helmet());
  app.use(cors({ origin: corsOrigin || true }));
  app.use(express.json({ limit: '4mb' }));

  const api = express.Router();

  api.get('/health', (_req, res) => res.json({ ok: true, time: new Date().toISOString() }));

  // ------------------------------------------------------------- auth
  const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 30,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many login attempts, try again later' },
  });

  api.post('/auth/login', loginLimiter, wrap(async (req, res) => {
    const email = String(req.body.email || '').trim().toLowerCase();
    const password = String(req.body.password || '');
    if (!email || !password) throw httpError(400, 'Email and password are required');
    const { data, error } = await db.from('admins').select('*').eq('email', email).maybeSingle();
    if (error) throw httpError(500, error.message);
    const ok = data && !data.disabled && (await bcrypt.compare(password, data.password_hash));
    if (!ok) throw httpError(401, 'Wrong email or password');
    const token = jwt.sign({ sub: data.id, role: data.role }, jwtSecret, { expiresIn: '30d' });
    res.json({ token, admin: publicAdmin(data) });
  }));

  const cache = new Map(); // id -> { admin, at }
  async function loadAdmin(id) {
    const hit = cache.get(id);
    if (hit && Date.now() - hit.at < 30000) return hit.admin;
    const { data, error } = await db.from('admins').select('*').eq('id', id).maybeSingle();
    if (error) throw httpError(500, error.message);
    cache.set(id, { admin: data, at: Date.now() });
    return data;
  }

  const auth = wrap(async (req, _res, next) => {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : '';
    let payload;
    try {
      payload = jwt.verify(token, jwtSecret);
    } catch {
      throw httpError(401, 'Not signed in');
    }
    const admin = await loadAdmin(payload.sub);
    if (!admin || admin.disabled) throw httpError(401, 'Account disabled or removed');
    req.admin = admin;
    next();
  });

  const needWrite = (req, _res, next) =>
    req.admin.role === 'viewer' ? next(httpError(403, 'Read-only account')) : next();
  const needSuper = (req, _res, next) =>
    req.admin.role === 'superadmin' ? next() : next(httpError(403, 'Superadmin only'));

  api.get('/auth/me', auth, (req, res) => res.json({ admin: publicAdmin(req.admin) }));

  // ----------------------------------------------------------- admins
  api.get('/admins', auth, needSuper, wrap(async (_req, res) => {
    const { data, error } = await db.from('admins').select('*').order('created_at');
    if (error) throw httpError(500, error.message);
    res.json({ admins: data.map(publicAdmin) });
  }));

  api.post('/admins', auth, needSuper, wrap(async (req, res) => {
    const email = String(req.body.email || '').trim().toLowerCase();
    const name = String(req.body.name || '').trim();
    const password = String(req.body.password || '');
    const role = String(req.body.role || 'admin');
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw httpError(400, 'Enter a valid email address');
    if (password.length < 8) throw httpError(400, 'Password must be at least 8 characters');
    if (!ROLES.includes(role)) throw httpError(400, 'Unknown role');
    const password_hash = await bcrypt.hash(password, 11);
    const { data, error } = await db.from('admins').insert({ email, name, password_hash, role }).select('*').single();
    if (error) throw httpError(error.code === '23505' ? 409 : 500, error.code === '23505' ? 'That email already has an account' : error.message);
    res.status(201).json({ admin: publicAdmin(data) });
  }));

  api.patch('/admins/:id', auth, needSuper, wrap(async (req, res) => {
    const patch = {};
    if (typeof req.body.name === 'string') patch.name = req.body.name.trim();
    if (typeof req.body.role === 'string') {
      if (!ROLES.includes(req.body.role)) throw httpError(400, 'Unknown role');
      patch.role = req.body.role;
    }
    if (typeof req.body.disabled === 'boolean') patch.disabled = req.body.disabled;
    if (typeof req.body.password === 'string' && req.body.password) {
      if (req.body.password.length < 8) throw httpError(400, 'Password must be at least 8 characters');
      patch.password_hash = await bcrypt.hash(req.body.password, 11);
    }
    if (req.params.id === req.admin.id && (patch.disabled || (patch.role && patch.role !== 'superadmin'))) {
      throw httpError(400, 'You cannot demote or disable your own account');
    }
    if (!Object.keys(patch).length) throw httpError(400, 'Nothing to change');
    const { error } = await db.from('admins').update(patch).eq('id', req.params.id);
    if (error) throw httpError(500, error.message);
    cache.delete(req.params.id);
    res.json({ ok: true });
  }));

  api.delete('/admins/:id', auth, needSuper, wrap(async (req, res) => {
    if (req.params.id === req.admin.id) throw httpError(400, 'You cannot delete your own account');
    const { error } = await db.from('admins').delete().eq('id', req.params.id);
    if (error) throw httpError(500, error.message);
    cache.delete(req.params.id);
    res.json({ ok: true });
  }));

  // ------------------------------------------------------------- sync
  api.get('/sync/snapshot', auth, wrap(async (_req, res) => {
    const [st, sc, sh, ru] = await Promise.all([
      db.from('students').select('*').order('id').limit(20000),
      db.from('sections').select('*').order('no'),
      db.from('shifts').select('*').order('no'),
      db.from('rules').select('*').eq('id', 1).maybeSingle(),
    ]);
    check(st, 'students'); check(sc, 'sections'); check(sh, 'shifts'); check(ru, 'rules');
    res.json({
      students: st.data.map(studentOut),
      sections: sc.data.map(sectionOut),
      shifts: sh.data.map(shiftOut),
      rules: ru.data ? rulesOut(ru.data) : null,
      serverTime: new Date().toISOString(),
    });
  }));

  // Last-write-wins: a row is only replaced if the incoming updatedAt is newer.
  async function lww(table, keyCol, rows) {
    if (!rows.length) return;
    const keys = rows.map((r) => r[keyCol]);
    const { data, error } = await db.from(table).select(`${keyCol}, updated_at`).in(keyCol, keys);
    if (error) throw httpError(500, error.message);
    const have = new Map(data.map((r) => [r[keyCol], new Date(r.updated_at).getTime()]));
    const fresh = rows.filter((r) => !have.has(r[keyCol]) || new Date(r.updated_at).getTime() >= have.get(r[keyCol]));
    if (!fresh.length) return;
    const up = await db.from(table).upsert(fresh, { onConflict: keyCol });
    if (up.error) throw httpError(500, `${table}: ${up.error.message}`);
  }

  api.post('/sync/push', auth, needWrite, wrap(async (req, res) => {
    const b = req.body || {};
    const students = (b.students || []).map((s) => {
      const id = Number(s.id);
      if (!Number.isInteger(id) || id < 1) throw httpError(400, 'Invalid student id');
      return {
        id, name: String(s.name || '').slice(0, 120),
        section: Math.min(16, Math.max(1, Number(s.section) || 1)),
        authority: Number(s.authority) === 1 ? 1 : 0,
        lrn: String(s.lrn || '').slice(0, 40), contact: String(s.contact || '').slice(0, 80),
        notes: String(s.notes || '').slice(0, 500),
        schedule: Array.isArray(s.schedule) ? s.schedule : null,
        deleted: !!s.deleted, updated_at: toIso(s.updatedAt),
      };
    });
    const sections = (b.sections || []).map((s) => ({
      no: Number(s.no), name: String(s.name || '').slice(0, 60),
      week: Array.isArray(s.week) && s.week.length === 7 ? s.week.map(Number) : [1, 1, 1, 1, 1, 1, 1],
      updated_at: toIso(s.updatedAt),
    })).filter((s) => s.no >= 1 && s.no <= 16);
    const shifts = (b.shifts || []).map((s) => ({
      no: Number(s.no), in1: s.in1 || '', out1: s.out1 || '', in2: s.in2 || '', out2: s.out2 || '',
      ot_in: s.otIn || '', ot_out: s.otOut || '', updated_at: toIso(s.updatedAt),
    })).filter((s) => s.no >= 1 && s.no <= 10);
    await lww('students', 'id', students);
    await lww('sections', 'no', sections);
    await lww('shifts', 'no', shifts);
    if (b.rules) {
      const r = b.rules;
      const row = {
        id: 1, company: String(r.company || '').slice(0, 80),
        late_allow: Number(r.lateAllow) || 0, early_allow: Number(r.earlyAllow) || 0,
        repeat_min: Number(r.repeatMin) || 3, schedule_mode: Number(r.scheduleMode) || 0,
        updated_at: toIso(r.updatedAt),
      };
      const { data } = await db.from('rules').select('updated_at').eq('id', 1).maybeSingle();
      if (!data || new Date(row.updated_at) >= new Date(data.updated_at)) {
        const up = await db.from('rules').upsert(row, { onConflict: 'id' });
        if (up.error) throw httpError(500, up.error.message);
      }
    }
    res.json({ ok: true });
  }));

  // -------------------------------------------------------------- logs
  api.post('/logs/bulk', auth, needWrite, wrap(async (req, res) => {
    const list = Array.isArray(req.body.logs) ? req.body.logs : [];
    if (list.length > 5000) throw httpError(413, 'Send at most 5000 punches per request');
    const rows = [];
    for (const l of list) {
      const id = Number(l.studentId);
      if (!Number.isInteger(id) || id < 1 || !TIME_RE.test(String(l.time))) continue;
      rows.push({
        student_id: id, name: String(l.name || '').slice(0, 120), dept: String(l.dept || '').slice(0, 60),
        punched_at: normTime(l.time), device_id: Number(l.deviceId) || 1,
      });
    }
    let inserted = 0;
    for (let i = 0; i < rows.length; i += 1000) {
      const chunk = rows.slice(i, i + 1000);
      const { data, error } = await db.from('attendance_logs')
        .upsert(chunk, { onConflict: 'student_id,punched_at,device_id', ignoreDuplicates: true })
        .select('id');
      if (error) throw httpError(500, error.message);
      inserted += data ? data.length : 0;
    }
    res.json({ received: list.length, valid: rows.length, inserted });
  }));

  api.get('/logs', auth, wrap(async (req, res) => {
    const after = Math.max(0, Number(req.query.after) || 0);
    const limit = Math.min(10000, Math.max(1, Number(req.query.limit) || 5000));
    const { data, error } = await db.from('attendance_logs')
      .select('id, student_id, name, dept, punched_at, device_id')
      .gt('id', after).order('id').limit(limit + 1);
    if (error) throw httpError(500, error.message);
    const hasMore = data.length > limit;
    const page = hasMore ? data.slice(0, limit) : data;
    res.json({
      logs: page.map((r) => ({
        studentId: r.student_id, name: r.name, dept: r.dept,
        time: normTime(r.punched_at), deviceId: r.device_id,
      })),
      cursor: page.length ? page[page.length - 1].id : after,
      hasMore,
    });
  }));

  app.use('/api', api);
  app.get('/', (_req, res) => res.json({ service: 'biometric-dashboard-server', ok: true }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    const status = err.status || 500;
    if (status >= 500) console.error(err);
    res.status(status).json({ error: status >= 500 ? 'Server error: ' + err.message : err.message });
  });

  return app;
}

module.exports = { createApp };
