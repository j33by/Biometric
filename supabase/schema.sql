-- CNHS Teachers Attendance: run once in Supabase: SQL Editor -> New query -> paste -> Run.
-- The Render server talks to these tables with the service-role key, so
-- row level security is switched on with NO public policies here: the anon key
-- (which ships in browsers and phones) can read nothing until teacher_app.sql adds
-- the per-person policies.
--
-- Time zone: every wall-clock value in these tables ("punched_at", the shift times,
-- leave dates) is PHILIPPINE time (UTC+8). The biometric device writes plain local
-- times with no zone, so they are stored exactly as written and never converted.
-- Only the *_at timestamptz columns (created_at / updated_at) are real instants.

create table if not exists admins (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  name          text not null default '',
  password_hash text not null,
  role          text not null default 'admin' check (role in ('superadmin','admin','viewer')),
  disabled      boolean not null default false,
  created_at    timestamptz not null default now()
);

-- One row per teacher enrolled on the biometric device.
create table if not exists teachers (
  id         integer primary key,                -- device user ID (typed on the device)
  name       text not null default '',
  faculty    integer not null default 1 check (faculty between 1 and 16),  -- device "Department" slot
  authority  integer not null default 0 check (authority in (0,1)),
  teacher_no text not null default '',           -- the teacher's DepEd / employee "Teacher ID"
  position   text not null default '',           -- Teacher I, Master Teacher, Adviser ...
  contact    text not null default '',
  notes      text not null default '',
  schedule   jsonb,
  deleted    boolean not null default false,
  updated_at timestamptz not null default now()
);

-- The device's 16 "Department" slots. The name is the SUBJECT taught; `week` holds the
-- shift number for Sunday..Saturday (0 = no duty).
create table if not exists faculty (
  no         integer primary key check (no between 1 and 16),
  name       text not null default '',
  week       jsonb not null default '[0,1,1,1,1,1,0]',
  updated_at timestamptz not null default now()
);

-- The device's 10 shifts: log-in / log-out times as 24-hour "HH:mm" Philippine time.
create table if not exists shifts (
  no         integer primary key check (no between 1 and 10),
  in1 text not null default '', out1 text not null default '',
  in2 text not null default '', out2 text not null default '',
  ot_in text not null default '', ot_out text not null default '',
  updated_at timestamptz not null default now()
);

-- Excused absences.
create table if not exists leaves (
  id         text primary key,
  teacher_id integer not null,
  from_date  date not null,
  to_date    date not null check (to_date >= from_date),
  type       text not null default 'Other',
  note       text not null default '',
  deleted    boolean not null default false,
  updated_at timestamptz not null default now()
);
create index if not exists leaves_teacher_idx on leaves (teacher_id);

create table if not exists rules (
  id               integer primary key default 1 check (id = 1),   -- single row
  company          text not null default '',
  late_allow       integer not null default 0,
  early_allow      integer not null default 0,
  repeat_min       integer not null default 3,
  schedule_mode    integer not null default 0,
  clock_offset_min integer not null default 0,    -- minutes added to device punches to match PH time
  updated_at       timestamptz not null default now()
);

-- Raw punches. The unique key is what makes re-importing the same USB export
-- (or two admins importing the same file) harmless.
create table if not exists attendance_logs (
  id         bigint generated always as identity primary key,
  teacher_id integer not null,                    -- device user ID
  name       text not null default '',
  dept       text not null default '',            -- device "Dept." = faculty slot name = subject
  punched_at timestamp not null,                  -- Philippine wall-clock time, no zone
  device_id  integer not null default 1,
  created_at timestamptz not null default now(),
  unique (teacher_id, punched_at, device_id)
);
create index if not exists attendance_logs_time_idx on attendance_logs (punched_at);

alter table admins          enable row level security;
alter table teachers        enable row level security;
alter table faculty         enable row level security;
alter table shifts          enable row level security;
alter table leaves          enable row level security;
alter table rules           enable row level security;
alter table attendance_logs enable row level security;
