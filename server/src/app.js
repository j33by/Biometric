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
const teacherOut = (r) => ({
  id: r.id, name: r.name, faculty: r.faculty, authority: r.authority,
  teacherNo: r.teacher_no, position: r.position, contact: r.contact, notes: r.notes,
  schedule: r.schedule, updatedAt: r.updated_at, deleted: r.deleted,
});
const facultyOut = (r) => ({ no: r.no, name: r.name, week: r.week, updatedAt: r.updated_at });
const shiftOut = (r) => ({
  no: r.no, in1: r.in1, out1: r.out1, in2: r.in2, out2: r.out2,
  otIn: r.ot_in, otOut: r.ot_out, updatedAt: r.updated_at,
});
const leaveOut = (r) => ({
  id: r.id, teacherId: r.teacher_id, from: String(r.from_date).slice(0, 10),
  to: String(r.to_date).slice(0, 10), type: r.type, note: r.note,
  updatedAt: r.updated_at, deleted: r.deleted,
});
const rulesOut = (r) => ({
  company: r.company, lateAllow: r.late_allow, earlyAllow: r.early_allow,
  repeatMin: r.repeat_min, scheduleMode: r.schedule_mode,
  clockOffsetMin: r.clock_offset_min || 0, updatedAt: r.updated_at,
});

// Everything in this system is Philippine wall-clock time (UTC+8, no DST). The server
// runs on UTC, so it must never format "now" with its own zone; it adds 8 hours itself.
const PH_OFFSET_MS = 8 * 60 * 60 * 1000;
const phNowString = () => new Date(Date.now() + PH_OFFSET_MS).toISOString().slice(0, 19).replace('T', ' ');
const HM_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const hm = (v) => (HM_RE.test(String(v || '')) ? String(v) : '');
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function createApp({ db, jwtSecret, corsOrigin }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // Render sits behind a proxy
  app.use(helmet());
  app.use(cors({ origin: corsOrigin || true }));
  app.use(express.json({ limit: '4mb' }));

  const api = express.Router();

  api.get('/health', (_req, res) => res.json({ ok: true, time: new Date().toISOString(), phTime: phNowString() }));

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

  // ----------------------------------------------- teacher phone accounts
  // The phone app binds a teacher's login to one teacher record. The same decisions the
  // phone's admin screens make (supabase/teacher_app.sql) are made here, from the desktop.
  // This server uses the service-role key, so the rules that row level security and the
  // admin_* functions enforce there are repeated below.
  const LINK_STATUSES = ['pending', 'approved', 'denied'];

  const accountOut = (l, t) => ({
    id: l.id, userId: l.user_id, email: l.email || '',
    accountName: l.account_name || '', pickedName: l.teacher_name || '',
    status: l.status, adminNote: l.admin_note || '',
    teacherId: l.teacher_id,
    teacherName: t ? t.name : (l.teacher_name || ''),
    teacherMissing: !t || !!t.deleted,
    faculty: t ? t.faculty : null, teacherNo: t ? t.teacher_no || '' : '', position: t ? t.position || '' : '',
    createdAt: l.created_at || null, reviewedAt: l.reviewed_at || null,
    unlinkRequested: !!l.unlink_requested, unlinkReason: l.unlink_reason || '',
    unlinkRequestedAt: l.unlink_requested_at || null,
  });

  async function loadLink(id) {
    const { data, error } = await db.from('teacher_links').select('*').eq('id', id).maybeSingle();
    if (error) throw httpError(500, error.message);
    if (!data) throw httpError(404, 'That account request no longer exists. Refresh the list.');
    return data;
  }

  async function loadTeacher(id) {
    const { data, error } = await db.from('teachers').select('*').eq('id', id).maybeSingle();
    if (error) throw httpError(500, error.message);
    return data;
  }

  api.get('/accounts', auth, needWrite, wrap(async (_req, res) => {
    const lk = await db.from('teacher_links').select('*').limit(5000);
    check(lk, 'accounts');
    const ids = [...new Set(lk.data.map((l) => l.teacher_id))];
    const byId = new Map();
    for (let i = 0; i < ids.length; i += 200) {
      const te = await db.from('teachers').select('id, name, faculty, teacher_no, position, deleted').in('id', ids.slice(i, i + 200));
      check(te, 'teachers');
      te.data.forEach((t) => byId.set(t.id, t));
    }
    const rows = lk.data
      .map((l) => accountOut(l, byId.get(l.teacher_id)))
      .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
    res.json({ accounts: rows });
  }));

  // Approve / deny / revoke, edit the display name or note, bind to another teacher and
  // rename the teacher record: any combination in one call. Nothing is written unless all
  // of it is valid.
  api.patch('/accounts/:id', auth, needWrite, wrap(async (req, res) => {
    const b = req.body || {};
    const link = await loadLink(req.params.id);
    const patch = { reviewed_at: new Date().toISOString() };

    if (b.status !== undefined) {
      if (!LINK_STATUSES.includes(b.status)) throw httpError(400, 'Status must be pending, approved or denied');
      patch.status = b.status;
    }
    let teacherId = link.teacher_id;
    if (b.teacherId !== undefined) {
      teacherId = Number(b.teacherId);
      if (!Number.isInteger(teacherId) || teacherId < 1) throw httpError(400, 'Invalid teacher id');
      patch.teacher_id = teacherId;
    }
    if (typeof b.accountName === 'string' && b.accountName.trim()) patch.account_name = b.accountName.trim().slice(0, 120);
    if (typeof b.note === 'string') patch.admin_note = b.note.trim().slice(0, 300);

    const status = patch.status || link.status;
    let newName = null;
    if (typeof b.teacherName === 'string') {
      newName = b.teacherName.trim().slice(0, 120);
      if (!newName) throw httpError(400, 'Name cannot be empty');
    }

    // The target teacher record must exist whenever it is being approved, rebound or renamed.
    if (status === 'approved' || b.teacherId !== undefined || newName !== null) {
      const t = await loadTeacher(teacherId);
      if (!t || t.deleted) throw httpError(400, 'That teacher record does not exist (has the desktop synced to the cloud?)');
    }
    // A teacher record can belong to only one approved account.
    if (status === 'approved') {
      const { data, error } = await db.from('teacher_links').select('id').eq('teacher_id', teacherId).eq('status', 'approved');
      if (error) throw httpError(500, error.message);
      if (data.some((x) => x.id !== link.id)) throw httpError(409, 'That teacher record is already linked to another approved account.');
    }

    const up = await db.from('teacher_links').update(patch).eq('id', link.id);
    if (up.error) {
      if (up.error.code === '23505') throw httpError(409, 'That teacher record is already linked to another approved account.');
      throw httpError(500, up.error.message);
    }
    if (newName !== null) {
      // updated_at is bumped so the desktop pulls the new name and writes it to Employee Form.xls.
      const rn = await db.from('teachers').update({ name: newName, updated_at: new Date().toISOString() }).eq('id', teacherId);
      if (rn.error) throw httpError(500, rn.error.message);
    }
    res.json({ ok: true });
  }));

  // Answer a teacher's request to unlink. approve = the link is deleted (they can bind again);
  // otherwise the link stays and the note is shown to the teacher.
  api.post('/accounts/:id/unlink', auth, needWrite, wrap(async (req, res) => {
    const link = await loadLink(req.params.id);
    if (!link.unlink_requested) throw httpError(409, 'This account has no open unlink request. Refresh the list.');
    if (req.body && req.body.approve === true) {
      const del = await db.from('teacher_links').delete().eq('id', link.id);
      if (del.error) throw httpError(500, del.error.message);
    } else {
      const note = String((req.body && req.body.note) || '').trim().slice(0, 300);
      const up = await db.from('teacher_links')
        .update({ unlink_requested: false, admin_note: note, reviewed_at: new Date().toISOString() })
        .eq('id', link.id);
      if (up.error) throw httpError(500, up.error.message);
    }
    res.json({ ok: true });
  }));

  // ------------------------------------------------------------ notices
  // Announcements the phone app shows to teachers (faculty null = every teacher).
  const noticeOut = (r) => ({
    id: r.id, title: r.title, body: r.body || '', faculty: r.faculty == null ? null : r.faculty,
    pinned: !!r.pinned, createdAt: r.created_at || null,
  });

  api.get('/notices', auth, needWrite, wrap(async (_req, res) => {
    const { data, error } = await db.from('notices').select('*').limit(500);
    if (error) throw httpError(500, error.message);
    const rows = data.map(noticeOut).sort((a, b) =>
      (b.pinned - a.pinned) || String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
    res.json({ notices: rows });
  }));

  api.post('/notices', auth, needWrite, wrap(async (req, res) => {
    const b = req.body || {};
    const title = String(b.title || '').trim();
    if (!title) throw httpError(400, 'A notice needs a title');
    if (title.length > 120) throw httpError(400, 'Title is too long (120 characters at most)');
    const body = String(b.body || '').trim();
    if (body.length > 2000) throw httpError(400, 'Message is too long (2000 characters at most)');
    let faculty = null;
    if (b.faculty !== null && b.faculty !== undefined) {
      faculty = Number(b.faculty);
      if (!Number.isInteger(faculty) || faculty < 1 || faculty > 16) throw httpError(400, 'Faculty must be 1 to 16');
    }
    const row = { title, body, faculty, pinned: b.pinned === true, created_at: new Date().toISOString() };
    const { data, error } = await db.from('notices').insert(row).select('*').single();
    if (error) throw httpError(500, error.message);
    res.status(201).json({ notice: noticeOut(data) });
  }));

  api.delete('/notices/:id', auth, needWrite, wrap(async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) throw httpError(400, 'Invalid notice id');
    const { data, error } = await db.from('notices').select('id').eq('id', id).maybeSingle();
    if (error) throw httpError(500, error.message);
    if (!data) throw httpError(404, 'That notice no longer exists. Refresh the list.');
    const del = await db.from('notices').delete().eq('id', id);
    if (del.error) throw httpError(500, del.error.message);
    res.json({ ok: true });
  }));

  // ------------------------------------------------------- phone admins
  // Phone-app admins are Supabase Auth users listed in app_admins (what the SQL one-liner
  // in the README did by hand). Looking a user up by email needs the Auth admin API.
  async function authUsers() {
    const out = [];
    for (let page = 1; page <= 50; page++) {
      const { data, error } = await db.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) throw httpError(500, error.message);
      const users = (data && data.users) || [];
      out.push(...users);
      if (users.length < 1000) break;
    }
    return out;
  }

  api.get('/phone-admins', auth, needSuper, wrap(async (_req, res) => {
    const { data, error } = await db.from('app_admins').select('*').limit(1000);
    if (error) throw httpError(500, error.message);
    const users = new Map((await authUsers()).map((u) => [u.id, u]));
    const rows = data.map((a) => ({
      userId: a.user_id, email: (users.get(a.user_id) || {}).email || '', createdAt: a.created_at || null,
    })).sort((a, b) => a.email.localeCompare(b.email));
    res.json({ admins: rows });
  }));

  api.post('/phone-admins', auth, needSuper, wrap(async (req, res) => {
    const email = String(req.body.email || '').trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw httpError(400, 'Enter a valid email address');
    const user = (await authUsers()).find((u) => String(u.email || '').toLowerCase() === email);
    if (!user) throw httpError(404, 'No phone account uses that email. They must sign up in the phone app first.');
    const { error } = await db.from('app_admins').insert({ user_id: user.id });
    if (error) throw httpError(error.code === '23505' ? 409 : 500, error.code === '23505' ? 'That account is already a phone admin' : error.message);
    res.status(201).json({ admin: { userId: user.id, email: user.email } });
  }));

  api.delete('/phone-admins/:userId', auth, needSuper, wrap(async (req, res) => {
    const { data, error } = await db.from('app_admins').select('user_id').eq('user_id', req.params.userId).maybeSingle();
    if (error) throw httpError(500, error.message);
    if (!data) throw httpError(404, 'That account is not a phone admin. Refresh the list.');
    const del = await db.from('app_admins').delete().eq('user_id', req.params.userId);
    if (del.error) throw httpError(500, del.error.message);
    res.json({ ok: true });
  }));

  // ------------------------------------------------------------- sync
  api.get('/sync/snapshot', auth, wrap(async (_req, res) => {
    const [te, fa, sh, lv, ru] = await Promise.all([
      db.from('teachers').select('*').order('id').limit(20000),
      db.from('faculty').select('*').order('no'),
      db.from('shifts').select('*').order('no'),
      db.from('leaves').select('*').order('from_date').limit(20000),
      db.from('rules').select('*').eq('id', 1).maybeSingle(),
    ]);
    check(te, 'teachers'); check(fa, 'faculty'); check(sh, 'shifts'); check(lv, 'leaves'); check(ru, 'rules');
    res.json({
      teachers: te.data.map(teacherOut),
      faculty: fa.data.map(facultyOut),
      shifts: sh.data.map(shiftOut),
      leaves: lv.data.map(leaveOut),
      rules: ru.data ? rulesOut(ru.data) : null,
      serverTime: new Date().toISOString(),
      phTime: phNowString(),
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
    const teachers = (b.teachers || []).map((s) => {
      const id = Number(s.id);
      if (!Number.isInteger(id) || id < 1) throw httpError(400, 'Invalid teacher id');
      return {
        id, name: String(s.name || '').slice(0, 120),
        faculty: Math.min(16, Math.max(1, Number(s.faculty) || 1)),
        authority: Number(s.authority) === 1 ? 1 : 0,
        teacher_no: String(s.teacherNo || '').slice(0, 40),
        position: String(s.position || '').slice(0, 80),
        contact: String(s.contact || '').slice(0, 80),
        notes: String(s.notes || '').slice(0, 500),
        schedule: Array.isArray(s.schedule) ? s.schedule : null,
        deleted: !!s.deleted, updated_at: toIso(s.updatedAt),
      };
    });
    const faculty = (b.faculty || []).map((s) => ({
      no: Number(s.no), name: String(s.name || '').slice(0, 60),
      week: Array.isArray(s.week) && s.week.length === 7 ? s.week.map((x) => Math.min(10, Math.max(0, Number(x) || 0))) : [0, 1, 1, 1, 1, 1, 0],
      updated_at: toIso(s.updatedAt),
    })).filter((s) => s.no >= 1 && s.no <= 16);
    // Shift times are Philippine wall-clock "HH:mm" (24-hour). Anything else is stored empty.
    const shifts = (b.shifts || []).map((s) => ({
      no: Number(s.no), in1: hm(s.in1), out1: hm(s.out1), in2: hm(s.in2), out2: hm(s.out2),
      ot_in: hm(s.otIn), ot_out: hm(s.otOut), updated_at: toIso(s.updatedAt),
    })).filter((s) => s.no >= 1 && s.no <= 10);
    const leaves = (b.leaves || []).map((l) => {
      const tid = Number(l.teacherId);
      if (!Number.isInteger(tid) || tid < 1) throw httpError(400, 'Invalid teacher id in leave');
      if (!DATE_RE.test(String(l.from)) || !DATE_RE.test(String(l.to))) throw httpError(400, 'Invalid leave date');
      return {
        id: String(l.id || '').slice(0, 60), teacher_id: tid,
        from_date: String(l.from), to_date: String(l.to) < String(l.from) ? String(l.from) : String(l.to),
        type: String(l.type || 'Other').slice(0, 40), note: String(l.note || '').slice(0, 300),
        deleted: !!l.deleted, updated_at: toIso(l.updatedAt),
      };
    }).filter((l) => l.id);
    await lww('teachers', 'id', teachers);
    await lww('faculty', 'no', faculty);
    await lww('shifts', 'no', shifts);
    await lww('leaves', 'id', leaves);
    if (b.rules) {
      const r = b.rules;
      const row = {
        id: 1, company: String(r.company || '').slice(0, 80),
        late_allow: Number(r.lateAllow) || 0, early_allow: Number(r.earlyAllow) || 0,
        repeat_min: Number(r.repeatMin) || 3, schedule_mode: Number(r.scheduleMode) || 0,
        clock_offset_min: Math.max(-1440, Math.min(1440, Math.round(Number(r.clockOffsetMin) || 0))),
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
      const id = Number(l.teacherId);
      if (!Number.isInteger(id) || id < 1 || !TIME_RE.test(String(l.time))) continue;
      rows.push({
        teacher_id: id, name: String(l.name || '').slice(0, 120), dept: String(l.dept || '').slice(0, 60),
        punched_at: normTime(l.time), device_id: Number(l.deviceId) || 1,
      });
    }
    let inserted = 0;
    for (let i = 0; i < rows.length; i += 1000) {
      const chunk = rows.slice(i, i + 1000);
      const { data, error } = await db.from('attendance_logs')
        .upsert(chunk, { onConflict: 'teacher_id,punched_at,device_id', ignoreDuplicates: true })
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
      .select('id, teacher_id, name, dept, punched_at, device_id')
      .gt('id', after).order('id').limit(limit + 1);
    if (error) throw httpError(500, error.message);
    const hasMore = data.length > limit;
    const page = hasMore ? data.slice(0, limit) : data;
    res.json({
      logs: page.map((r) => ({
        teacherId: r.teacher_id, name: r.name, dept: r.dept,
        time: normTime(r.punched_at), deviceId: r.device_id,
      })),
      cursor: page.length ? page[page.length - 1].id : after,
      hasMore,
    });
  }));

  app.use('/api', api);
  app.get('/', (_req, res) => res.json({ service: 'cnhs-teacher-attendance-server', ok: true }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    const status = err.status || 500;
    if (status >= 500) console.error(err);
    res.status(status).json({ error: status >= 500 ? 'Server error: ' + err.message : err.message });
  });

  return app;
}

module.exports = { createApp, phNowString };
