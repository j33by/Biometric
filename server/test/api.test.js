'use strict';
// Runs the real Express app against an in-memory stand-in for Supabase.
const assert = require('assert');
const http = require('http');
const bcrypt = require('bcryptjs');
const { createApp } = require('../src/app');

function fakeDb(seed) {
  const tables = { admins: [], teachers: [], faculty: [], shifts: [], leaves: [], rules: [], attendance_logs: [], ...seed };
  let nextId = 1;
  const uniq = { attendance_logs: ['teacher_id', 'punched_at', 'device_id'], admins: ['email'] };
  return {
    tables,
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
            if (name === 'attendance_logs') n.id = nextId++;
            tables[name].push(n);
            out.push(n);
          }
          return { data: q.sel ? out : null, error: null };
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

  // disabling an admin cuts the token off
  assert.equal((await call('PATCH', `/admins/${mk.json.admin.id}`, { disabled: true }, tok)).status, 200);
  await new Promise((r2) => setTimeout(r2, 10));
  server.close();
  console.log('server tests passed');
  process.exit(0);
}
main().catch((e) => { console.error(e); process.exit(1); });
