'use strict';
// Runs the real Express app against an in-memory stand-in for Supabase.
const assert = require('assert');
const http = require('http');
const bcrypt = require('bcryptjs');
const { createApp } = require('../src/app');

function fakeDb(seed) {
  const tables = { admins: [], teachers: [], faculty: [], shifts: [], leaves: [], rules: [], attendance_logs: [], teacher_links: [], notices: [], app_admins: [], ...seed };
  let nextId = 1;
  const uniq = { attendance_logs: ['teacher_id', 'punched_at', 'device_id'], admins: ['email'], app_admins: ['user_id'] };
  return {
    tables,
    auth: { admin: { listUsers: async () => ({ data: { users: tables.auth_users || [] }, error: null }) } },
    from(name) {
      const q = { filters: [], order: null, lim: null, op: 'select', payload: null, opts: {}, single: false, sel: false };
      const rows = () => {
        let r = tables[name].filter((x) => q.filters.every((f) => f(x)));
        if (q.order) r = [...r].sort((a, b) => (a[q.order] > b[q.order] ? 1 : -1));
        if (q.lim != null) r = r.slice(0, q.lim);
        return r;
      };
      const run = () => {
        if (q.op === 'insert' || q.op === 'upsert') {
          const list = Array.isArray(q.payload) ? q.payload : [q.payload];
          const out = [];
          for (const row of list) {
            const keys = q.op === 'upsert' ? (q.opts.onConflict || 'id').split(',') : uniq[name] || ['id'];
            const hit = tables[name].find((x) => keys.every((k) => String(x[k]) === String(row[k])) && row[keys[0]] !== undefined);
            if (hit && q.op === 'insert') return { data: null, error: { code: '23505', message: 'dup' } };
            if (hit) { if (!q.opts.ignoreDuplicates) Object.assign(hit, row); continue; }
            const n = { ...row };
            if (name === 'admins') n.id = n.id || 'adm-' + nextId++;
            if (name === 'attendance_logs' || name === 'notices') n.id = nextId++;
            tables[name].push(n);
            out.push(n);
          }
          return { data: q.sel ? (q.single ? out[0] || null : out) : null, error: null };
        }
        if (q.op === 'update') { rows().forEach((r) => Object.assign(r, q.payload)); return { data: null, error: null }; }
        if (q.op === 'delete') { const kill = new Set(rows()); tables[name] = tables[name].filter((x) => !kill.has(x)); return { data: null, error: null }; }
        const r = rows();
        if (q.single) return { data: r[0] || null, error: null };
        return { data: r, error: null };
      };
      const b = {
        select() { q.sel = true; return b; },
        eq(c, v) { q.filters.push((x) => x[c] === v); return b; },
        gt(c, v) { q.filters.push((x) => x[c] > v); return b; },
        in(c, v) { q.filters.push((x) => v.includes(x[c])); return b; },
        order(c) { q.order = c; return b; },
        limit(n) { q.lim = n; return b; },
        maybeSingle() { q.single = true; return Promise.resolve(run()); },
        single() { q.single = true; return Promise.resolve(run()); },
        insert(p) { q.op = 'insert'; q.payload = p; return b; },
        upsert(p, o) { q.op = 'upsert'; q.payload = p; q.opts = o || {}; return b; },
        update(p) { q.op = 'update'; q.payload = p; return b; },
        delete() { q.op = 'delete'; return b; },
        then(res, rej) { return Promise.resolve(run()).then(res, rej); },
      };
      return b;
    },
  };
}

async function main() {
  const db = fakeDb();
  db.tables.admins.push({ id: 'a1', email: 'boss@school.test', name: 'Boss', role: 'superadmin', disabled: false,
    password_hash: await bcrypt.hash('correct horse', 4), created_at: '2026-01-01' });
  const app = createApp({ db, jwtSecret: 'x'.repeat(32) });
  const server = http.createServer(app).listen(0);
  const base = `http://127.0.0.1:${server.address().port}/api`;
  const call = async (m, p, body, tok) => {
    const r = await fetch(base + p, { method: m, headers: { 'Content-Type': 'application/json', ...(tok ? { Authorization: 'Bearer ' + tok } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, json: await r.json().catch(() => null) };
  };

  const health = await call('GET', '/health');
  assert.equal(health.status, 200);
  // the server runs on UTC but must report Philippine time (UTC+8)
  const phMs = Date.parse(health.json.phTime.replace(' ', 'T') + 'Z'), utcMs = Date.parse(health.json.time);
  assert.ok(Math.abs(phMs - utcMs - 8 * 3600 * 1000) < 5000, 'phTime is UTC+8');
  assert.equal((await call('GET', '/sync/snapshot')).status, 401, 'needs auth');
  assert.equal((await call('POST', '/auth/login', { email: 'boss@school.test', password: 'nope' })).status, 401);
  const login = await call('POST', '/auth/login', { email: 'BOSS@school.test', password: 'correct horse' });
  assert.equal(login.status, 200); const tok = login.json.token;

  // admins
  assert.equal((await call('POST', '/admins', { email: 'bad', password: 'longenough', role: 'admin' }, tok)).status, 400);
  assert.equal((await call('POST', '/admins', { email: 'a@b.co', password: 'short', role: 'admin' }, tok)).status, 400);
  const mk = await call('POST', '/admins', { email: 'teacher@school.test', name: 'T', password: 'longenough', role: 'viewer' }, tok);
  assert.equal(mk.status, 201);
  assert.equal((await call('POST', '/admins', { email: 'teacher@school.test', password: 'longenough' }, tok)).status, 409);
  const vt = (await call('POST', '/auth/login', { email: 'teacher@school.test', password: 'longenough' })).json.token;
  assert.equal((await call('GET', '/admins', null, vt)).status, 403, 'viewer is not superadmin');
  assert.equal((await call('POST', '/logs/bulk', { logs: [] }, vt)).status, 403, 'viewer is read-only');
  assert.equal((await call('GET', '/logs', null, vt)).status, 200, 'viewer can read');
  assert.equal((await call('PATCH', '/admins/a1', { disabled: true }, tok)).status, 400, 'cannot disable self');

  // teachers, last-write-wins
  const t1 = '2026-11-02T01:00:00.000Z', t0 = '2026-11-01T01:00:00.000Z';
  await call('POST', '/sync/push', { teachers: [{ id: 5, name: 'Ruloma, Rosana P.', faculty: 2, authority: 0, teacherNo: '1234567', position: 'Teacher I', updatedAt: t1 }] }, tok);
  await call('POST', '/sync/push', { teachers: [{ id: 5, name: 'OLD STALE', faculty: 2, updatedAt: t0 }] }, tok);
  let snap = (await call('GET', '/sync/snapshot', null, tok)).json;
  assert.equal(snap.teachers.length, 1); assert.equal(snap.teachers[0].name, 'Ruloma, Rosana P.', 'stale write must lose');
  assert.equal(snap.teachers[0].teacherNo, '1234567'); assert.equal(snap.teachers[0].position, 'Teacher I');
  await call('POST', '/sync/push', { teachers: [{ id: 5, name: 'Ruloma, R. P.', faculty: 2, updatedAt: '2026-11-03T00:00:00Z' }], rules: { company: 'CNHS', lateAllow: 5, clockOffsetMin: 480, updatedAt: t1 } }, tok);
  snap = (await call('GET', '/sync/snapshot', null, tok)).json;
  assert.equal(snap.teachers[0].name, 'Ruloma, R. P.'); assert.equal(snap.rules.lateAllow, 5);
  assert.equal(snap.rules.clockOffsetMin, 480, 'device clock correction is stored');
  assert.ok(snap.phTime, 'snapshot carries Philippine time');
  assert.equal((await call('POST', '/sync/push', { teachers: [{ id: 'x' }] }, tok)).status, 400, 'bad teacher id');

  // faculty + shifts: Philippine 24-hour times only
  await call('POST', '/sync/push', {
    faculty: [{ no: 1, name: 'Research 12', week: [0, 1, 1, 0, 1, 2, 0], updatedAt: t1 }, { no: 99, name: 'ignored', updatedAt: t1 }],
    shifts: [{ no: 1, in1: '07:50', out1: '09:50', updatedAt: t1 }, { no: 3, in1: '1:00 PM', out1: '25:00', updatedAt: t1 }],
  }, tok);
  snap = (await call('GET', '/sync/snapshot', null, tok)).json;
  assert.equal(snap.faculty.length, 1, 'slot 99 is rejected');
  assert.deepEqual(snap.faculty[0].week, [0, 1, 1, 0, 1, 2, 0]);
  assert.equal(snap.shifts.find((s) => s.no === 1).in1, '07:50');
  assert.equal(snap.shifts.find((s) => s.no === 3).in1, '', 'non-24-hour text is not stored');
  assert.equal(snap.shifts.find((s) => s.no === 3).out1, '');

  // leaves
  await call('POST', '/sync/push', { leaves: [{ id: 'L1', teacherId: 5, from: '2026-11-02', to: '2026-11-03', type: 'Sick leave', note: 'flu', updatedAt: t1 }] }, tok);
  await call('POST', '/sync/push', { leaves: [{ id: 'L1', teacherId: 5, from: '2026-11-02', to: '2026-11-09', type: 'OLD', updatedAt: t0 }] }, tok);
  snap = (await call('GET', '/sync/snapshot', null, tok)).json;
  assert.equal(snap.leaves.length, 1); assert.equal(snap.leaves[0].to, '2026-11-03', 'stale leave loses'); assert.equal(snap.leaves[0].type, 'Sick leave');
  await call('POST', '/sync/push', { leaves: [{ id: 'L1', teacherId: 5, from: '2026-11-02', to: '2026-11-03', type: 'Sick leave', deleted: true, updatedAt: '2026-11-04T00:00:00Z' }] }, tok);
  snap = (await call('GET', '/sync/snapshot', null, tok)).json;
  assert.equal(snap.leaves[0].deleted, true, 'deleted leave is kept as a tombstone');
  assert.equal((await call('POST', '/sync/push', { leaves: [{ id: 'L2', teacherId: 5, from: 'nope', to: '2026-11-03' }] }, tok)).status, 400, 'bad leave date');
  assert.equal((await call('POST', '/sync/push', { leaves: [] }, vt)).status, 403, 'viewer cannot push');

  // logs: dedupe + paging
  const L = (i, t) => ({ teacherId: i, name: 'Mejorada', dept: 'Research 12', time: t, deviceId: 1 });
  const batch = [L(1, '2026-11-02 10:28:36'), L(1, '2026-11-02 10:56:33'), L(1, '2026-11-02 10:28:36'), { teacherId: 'x', time: 'bad' }];
  let r = await call('POST', '/logs/bulk', { logs: batch }, tok);
  assert.deepEqual([r.json.valid, r.json.inserted], [3, 2], 'in-batch duplicate collapsed');
  r = await call('POST', '/logs/bulk', { logs: batch }, tok);
  assert.equal(r.json.inserted, 0, 're-import inserts nothing');
  await call('POST', '/logs/bulk', { logs: [L(2, '2026-11-02T12:00:00')] }, tok);
  let page = (await call('GET', '/logs?after=0&limit=2', null, tok)).json;
  assert.equal(page.logs.length, 2); assert.equal(page.hasMore, true);
  assert.equal(page.logs[0].time, '2026-11-02 10:28:36');
  page = (await call('GET', `/logs?after=${page.cursor}&limit=2`, null, tok)).json;
  assert.equal(page.logs.length, 1); assert.equal(page.hasMore, false);
  assert.equal(page.logs[0].time, '2026-11-02 12:00:00');

  // teacher phone accounts (binding approvals from the desktop)
  await call('POST', '/sync/push', { teachers: [{ id: 6, name: 'Labrador, Alicia C.', faculty: 3, updatedAt: t1 }] }, tok);
  db.tables.teacher_links.push(
    { id: 'k1', user_id: 'u1', teacher_id: 5, teacher_name: 'Ruloma', account_name: 'Rosana', email: 'ros@school.test', status: 'pending', admin_note: '', created_at: '2026-11-01T01:00:00Z', unlink_requested: false },
    { id: 'k2', user_id: 'u2', teacher_id: 5, teacher_name: 'Ruloma', account_name: 'Alicia', email: 'ali@school.test', status: 'pending', admin_note: '', created_at: '2026-11-02T01:00:00Z', unlink_requested: false },
  );
  assert.equal((await call('GET', '/accounts', null, vt)).status, 403, 'viewer cannot see accounts');
  assert.equal((await call('PATCH', '/accounts/k1', { status: 'approved' }, vt)).status, 403, 'viewer cannot approve');
  let acc = (await call('GET', '/accounts', null, tok)).json.accounts;
  assert.deepEqual(acc.map((a) => a.id), ['k2', 'k1'], 'newest request first');
  assert.equal(acc[1].teacherName, 'Ruloma, R. P.', 'shows the current teacher record name');
  assert.equal(acc[1].email, 'ros@school.test');
  assert.equal((await call('PATCH', '/accounts/nope', { status: 'approved' }, tok)).status, 404);
  assert.equal((await call('PATCH', '/accounts/k1', { status: 'maybe' }, tok)).status, 400, 'bad status');
  assert.equal((await call('PATCH', '/accounts/k1', { teacherId: 999 }, tok)).status, 400, 'unknown teacher');
  assert.equal((await call('PATCH', '/accounts/k1', { teacherName: '  ' }, tok)).status, 400, 'empty name');
  assert.equal((await call('PATCH', '/accounts/k1', { status: 'approved' }, tok)).status, 200);
  assert.equal(db.tables.teacher_links.find((l) => l.id === 'k1').status, 'approved');
  assert.ok(db.tables.teacher_links.find((l) => l.id === 'k1').reviewed_at, 'review time recorded');
  assert.equal((await call('PATCH', '/accounts/k2', { status: 'approved' }, tok)).status, 409, 'one approved account per teacher record');
  assert.equal(db.tables.teacher_links.find((l) => l.id === 'k2').status, 'pending', 'a refused approval changes nothing');
  assert.equal((await call('PATCH', '/accounts/k2', { status: 'approved', teacherId: 6, accountName: 'Alicia L.', note: 'ok' }, tok)).status, 200, 'rebind then approve');
  const k2 = db.tables.teacher_links.find((l) => l.id === 'k2');
  assert.deepEqual([k2.teacher_id, k2.account_name, k2.admin_note, k2.status], [6, 'Alicia L.', 'ok', 'approved']);
  const before = new Date(db.tables.teachers.find((t) => t.id === 6).updated_at).getTime();
  assert.equal((await call('PATCH', '/accounts/k2', { teacherName: 'Labrador, Alicia Cruz' }, tok)).status, 200);
  const t6 = db.tables.teachers.find((t) => t.id === 6);
  assert.equal(t6.name, 'Labrador, Alicia Cruz', 'teacher record renamed');
  assert.ok(new Date(t6.updated_at).getTime() > before, 'rename bumps updated_at so the desktop pulls it');
  snap = (await call('GET', '/sync/snapshot', null, tok)).json;
  assert.equal(snap.teachers.find((t) => t.id === 6).name, 'Labrador, Alicia Cruz');
  assert.equal((await call('PATCH', '/accounts/k1', { status: 'denied', note: 'wrong person' }, tok)).status, 200, 'revoke');
  assert.deepEqual([db.tables.teacher_links[0].status, db.tables.teacher_links[0].admin_note], ['denied', 'wrong person']);

  // unlink requests
  assert.equal((await call('POST', '/accounts/k2/unlink', { approve: true }, tok)).status, 409, 'no request to answer');
  k2.unlink_requested = true; k2.unlink_reason = 'new phone';
  acc = (await call('GET', '/accounts', null, tok)).json.accounts;
  assert.equal(acc.find((a) => a.id === 'k2').unlinkRequested, true);
  assert.equal(acc.find((a) => a.id === 'k2').unlinkReason, 'new phone');
  assert.equal((await call('POST', '/accounts/k2/unlink', { approve: false, note: 'Not yet' }, vt)).status, 403);
  assert.equal((await call('POST', '/accounts/k2/unlink', { approve: false, note: 'Not yet' }, tok)).status, 200, 'keep linked');
  assert.deepEqual([k2.unlink_requested, k2.admin_note, k2.status], [false, 'Not yet', 'approved']);
  k2.unlink_requested = true;
  assert.equal((await call('POST', '/accounts/k2/unlink', { approve: true }, tok)).status, 200, 'approve unlink');
  assert.equal(db.tables.teacher_links.some((l) => l.id === 'k2'), false, 'link deleted');
  assert.equal((await call('PATCH', '/accounts/k1', { status: 'approved', teacherId: 6 }, tok)).status, 200, 'the record is free to bind again');

  // notices
  assert.equal((await call('GET', '/notices', null, vt)).status, 403, 'viewer cannot manage notices');
  assert.equal((await call('POST', '/notices', { title: '  ' }, tok)).status, 400, 'title required');
  assert.equal((await call('POST', '/notices', { title: 'x', faculty: 99 }, tok)).status, 400, 'bad faculty');
  const n1 = await call('POST', '/notices', { title: 'Flag ceremony', body: 'Monday 7:30', faculty: null, pinned: false }, tok);
  assert.equal(n1.status, 201);
  const n2 = await call('POST', '/notices', { title: 'Research 12 meeting', faculty: 1, pinned: true }, tok);
  let notes = (await call('GET', '/notices', null, tok)).json.notices;
  assert.deepEqual(notes.map((n) => n.title), ['Research 12 meeting', 'Flag ceremony'], 'pinned first');
  assert.equal(notes[0].faculty, 1); assert.equal(notes[1].faculty, null, 'null = every teacher');
  assert.equal((await call('DELETE', `/notices/${n1.json.notice.id}`, null, vt)).status, 403);
  assert.equal((await call('DELETE', `/notices/${n1.json.notice.id}`, null, tok)).status, 200);
  assert.equal((await call('DELETE', `/notices/${n1.json.notice.id}`, null, tok)).status, 404, 'already gone');
  assert.equal((await call('GET', '/notices', null, tok)).json.notices.length, 1);

  // phone admins (superadmin only; looked up in Supabase Auth by email)
  db.tables.auth_users = [{ id: 'u1', email: 'Ros@School.test' }, { id: 'u2', email: 'ali@school.test' }];
  assert.equal((await call('GET', '/phone-admins', null, vt)).status, 403, 'superadmin only');
  assert.equal((await call('POST', '/phone-admins', { email: 'nope' }, tok)).status, 400);
  assert.equal((await call('POST', '/phone-admins', { email: 'ghost@school.test' }, tok)).status, 404, 'must have signed up');
  assert.equal((await call('POST', '/phone-admins', { email: 'ros@school.test' }, tok)).status, 201, 'email match ignores case');
  assert.equal((await call('POST', '/phone-admins', { email: 'ros@school.test' }, tok)).status, 409, 'already admin');
  let pa = (await call('GET', '/phone-admins', null, tok)).json.admins;
  assert.deepEqual(pa.map((a) => [a.userId, a.email]), [['u1', 'Ros@School.test']]);
  assert.equal((await call('DELETE', '/phone-admins/u2', null, tok)).status, 404);
  assert.equal((await call('DELETE', '/phone-admins/u1', null, tok)).status, 200);
  assert.equal((await call('GET', '/phone-admins', null, tok)).json.admins.length, 0);

  // disabling an admin cuts the token off
  assert.equal((await call('PATCH', `/admins/${mk.json.admin.id}`, { disabled: true }, tok)).status, 200);
  await new Promise((r2) => setTimeout(r2, 10));
  server.close();
  console.log('server tests passed');
  process.exit(0);
}
main().catch((e) => { console.error(e); process.exit(1); });
