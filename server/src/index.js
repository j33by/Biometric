'use strict';
const { createClient } = require('@supabase/supabase-js');
const bcrypt = require('bcryptjs');
const { createApp } = require('./app');

const { SUPABASE_URL, SUPABASE_SERVICE_KEY, JWT_SECRET, ADMIN_EMAIL, ADMIN_PASSWORD, CORS_ORIGIN } = process.env;
const PORT = Number(process.env.PORT) || 3000;

for (const [k, v] of Object.entries({ SUPABASE_URL, SUPABASE_SERVICE_KEY, JWT_SECRET })) {
  if (!v) {
    console.error(`Missing environment variable ${k}`);
    process.exit(1);
  }
}
if (JWT_SECRET.length < 24) {
  console.error('JWT_SECRET must be at least 24 characters');
  process.exit(1);
}

const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { persistSession: false } });

async function bootstrap() {
  if (!ADMIN_EMAIL || !ADMIN_PASSWORD) return;
  const { data, error } = await db.from('admins').select('id').limit(1);
  if (error) {
    console.error('Could not reach Supabase (did you run supabase/schema.sql?):', error.message);
    return;
  }
  if (data.length === 0) {
    const password_hash = await bcrypt.hash(ADMIN_PASSWORD, 11);
    const ins = await db.from('admins').insert({
      email: ADMIN_EMAIL.trim().toLowerCase(), name: 'Owner', password_hash, role: 'superadmin',
    });
    console.log(ins.error ? 'Bootstrap failed: ' + ins.error.message : `Created first superadmin ${ADMIN_EMAIL}`);
  }
}

createApp({ db, jwtSecret: JWT_SECRET, corsOrigin: CORS_ORIGIN }).listen(PORT, () => {
  console.log(`API listening on :${PORT}`);
  bootstrap().catch((e) => console.error(e));
});
