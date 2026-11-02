-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.
-- The Render server talks to these tables with the service-role key, so
-- row level security is switched on with NO public policies: the anon key
-- (which ships in browsers) can read nothing.

create table if not exists admins (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  name          text not null default '',
  password_hash text not null,
  role          text not null default 'admin' check (role in ('superadmin','admin','viewer')),
  disabled      boolean not null default false,
  created_at    timestamptz not null default now()
);

create table if not exists students (
  id         integer primary key,                -- device user ID
  name       text not null default '',
  section    integer not null default 1 check (section between 1 and 16),
  authority  integer not null default 0 check (authority in (0,1)),
  lrn        text not null default '',
  contact    text not null default '',
  notes      text not null default '',
  schedule   jsonb,
  deleted    boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists sections (
  no         integer primary key check (no between 1 and 16),
  name       text not null default '',
  week       jsonb not null default '[1,1,1,1,1,1,1]',
  updated_at timestamptz not null default now()
);

create table if not exists shifts (
  no         integer primary key check (no between 1 and 10),
  in1 text not null default '', out1 text not null default '',
  in2 text not null default '', out2 text not null default '',
  ot_in text not null default '', ot_out text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists rules (
  id            integer primary key default 1 check (id = 1),   -- single row
  company       text not null default '',
  late_allow    integer not null default 0,
  early_allow   integer not null default 0,
  repeat_min    integer not null default 3,
  schedule_mode integer not null default 0,
  updated_at    timestamptz not null default now()
);

-- Raw punches. The unique key is what makes re-importing the same USB export
-- (or two admins importing the same file) harmless.
create table if not exists attendance_logs (
  id         bigint generated always as identity primary key,
  student_id integer not null,
  name       text not null default '',
  dept       text not null default '',
  punched_at timestamp not null,                  -- device wall-clock time, no zone
  device_id  integer not null default 1,
  created_at timestamptz not null default now(),
  unique (student_id, punched_at, device_id)
);
create index if not exists attendance_logs_time_idx on attendance_logs (punched_at);

alter table admins          enable row level security;
alter table students        enable row level security;
alter table sections        enable row level security;
alter table shifts          enable row level security;
alter table rules           enable row level security;
alter table attendance_logs enable row level security;
