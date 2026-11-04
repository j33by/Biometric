-- ============================================================================
-- CNHS Teachers Attendance - COMPLETE database setup. ONE file, run it once.
--
--   Supabase > SQL Editor > New query > paste this whole file > Run.
--
-- Safe to run on ANY starting point, and safe to run again:
--   * a brand-new project,
--   * a project that already has the old STUDENT version (students / sections / student_links),
--   * a project where an earlier attempt stopped half way.
-- Nothing is deleted. Old student tables are simply left alone (see the optional clean-up at the end).
-- With this file you do NOT need schema.sql, teacher_app.sql, unlink_request.sql or
-- migrate_from_student_version.sql (they are kept for reference).
--
-- Time zone: every wall-clock value (punched_at, shift times, leave dates) is PHILIPPINE time (UTC+8),
-- stored exactly as the biometric device writes it, never converted.
-- ============================================================================

-- ---------------------------------------------------------------- 1. clear what depends on old functions
-- Policies are re-created in step 6. Dropping them first lets the functions be replaced cleanly.
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('attendance_logs','notices','teachers','faculty','shifts','rules','leaves',
                        'teacher_links','students','sections','student_links','admins')
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

drop function if exists my_student_id();
drop function if exists my_section();
drop function if exists search_students(text);
drop function if exists admin_rename_student(integer, text);
drop function if exists my_teacher_id();
drop function if exists my_faculty();
drop function if exists search_teachers(text);
drop function if exists logged_days(date, date);
drop function if exists admin_review_link(uuid, text, integer, text, text);
drop function if exists admin_rename_teacher(integer, text);
drop function if exists admin_save_shift(integer, text, text, text, text, text, text);
drop function if exists request_unlink(text);
drop function if exists cancel_unlink_request();
drop function if exists admin_resolve_unlink(uuid, boolean, text);
drop function if exists is_app_admin();

-- ---------------------------------------------------------------- 2. tables the desktop server uses
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
  id         integer primary key,                 -- device user ID
  name       text not null default '',
  faculty    integer not null default 1,          -- device "Department" slot 1..16
  authority  integer not null default 0,
  teacher_no text not null default '',            -- DepEd / employee "Teacher ID"
  position   text not null default '',
  contact    text not null default '',
  notes      text not null default '',
  schedule   jsonb,
  deleted    boolean not null default false,
  updated_at timestamptz not null default now()
);

-- The device's 16 "Department" slots: name = the SUBJECT, week = shift number Sunday..Saturday.
create table if not exists faculty (
  no         integer primary key,
  name       text not null default '',
  week       jsonb not null default '[0,1,1,1,1,1,0]',
  updated_at timestamptz not null default now()
);

-- The device's 10 shifts: 24-hour "HH:mm" Philippine time.
create table if not exists shifts (
  no         integer primary key,
  in1 text not null default '', out1 text not null default '',
  in2 text not null default '', out2 text not null default '',
  ot_in text not null default '', ot_out text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists leaves (
  id         text primary key,
  teacher_id integer not null,
  from_date  date not null,
  to_date    date not null,
  type       text not null default 'Other',
  note       text not null default '',
  deleted    boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists rules (
  id               integer primary key default 1,
  company          text not null default '',
  late_allow       integer not null default 0,
  early_allow      integer not null default 0,
  repeat_min       integer not null default 3,
  schedule_mode    integer not null default 0,
  clock_offset_min integer not null default 0,
  updated_at       timestamptz not null default now()
);

create table if not exists attendance_logs (
  id         bigint generated always as identity primary key,
  teacher_id integer not null,
  name       text not null default '',
  dept       text not null default '',
  punched_at timestamp not null,                  -- Philippine wall-clock, no zone
  device_id  integer not null default 1,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- 3. bring OLD tables up to date
-- (only does something when an older version of a table is already there)
do $$
begin
  -- punches: student_id -> teacher_id
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='attendance_logs' and column_name='student_id')
     and not exists (select 1 from information_schema.columns where table_schema='public' and table_name='attendance_logs' and column_name='teacher_id') then
    alter table attendance_logs rename column student_id to teacher_id;
  end if;

  -- teachers: older shapes
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='teachers' and column_name='section')
     and not exists (select 1 from information_schema.columns where table_schema='public' and table_name='teachers' and column_name='faculty') then
    alter table teachers rename column section to faculty;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='teachers' and column_name='lrn')
     and not exists (select 1 from information_schema.columns where table_schema='public' and table_name='teachers' and column_name='teacher_no') then
    alter table teachers rename column lrn to teacher_no;
  end if;

  -- notices: section -> faculty
  if to_regclass('public.notices') is not null
     and exists (select 1 from information_schema.columns where table_schema='public' and table_name='notices' and column_name='section')
     and not exists (select 1 from information_schema.columns where table_schema='public' and table_name='notices' and column_name='faculty') then
    alter table notices rename column section to faculty;
  end if;
end $$;

alter table teachers add column if not exists faculty    integer not null default 1;
alter table teachers add column if not exists authority  integer not null default 0;
alter table teachers add column if not exists teacher_no text    not null default '';
alter table teachers add column if not exists position   text    not null default '';
alter table teachers add column if not exists contact    text    not null default '';
alter table teachers add column if not exists notes      text    not null default '';
alter table teachers add column if not exists schedule   jsonb;
alter table teachers add column if not exists deleted    boolean not null default false;
alter table teachers add column if not exists updated_at timestamptz not null default now();

alter table faculty  add column if not exists name       text not null default '';
alter table faculty  add column if not exists week       jsonb not null default '[0,1,1,1,1,1,0]';
alter table faculty  add column if not exists updated_at timestamptz not null default now();

alter table rules    add column if not exists clock_offset_min integer not null default 0;

alter table attendance_logs add column if not exists name      text    not null default '';
alter table attendance_logs add column if not exists dept      text    not null default '';
alter table attendance_logs add column if not exists device_id integer not null default 1;

-- the server upserts punches on this key (re-importing the same USB file is harmless)
create unique index if not exists attendance_logs_teacher_time_uniq on attendance_logs (teacher_id, punched_at, device_id);
create index if not exists attendance_logs_time_idx on attendance_logs (punched_at);
create index if not exists leaves_teacher_idx on leaves (teacher_id);

-- ---------------------------------------------------------------- 4. phone-app tables
create table if not exists app_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists teacher_links (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  teacher_id   integer not null references teachers(id) on delete cascade,
  teacher_name text not null default '',
  account_name text not null default '',
  email        text not null default '',
  status       text not null default 'pending' check (status in ('pending','approved','denied')),
  admin_note   text not null default '',
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz,
  unlink_requested    boolean not null default false,
  unlink_reason       text    not null default '',
  unlink_requested_at timestamptz
);
alter table teacher_links add column if not exists unlink_requested    boolean not null default false;
alter table teacher_links add column if not exists unlink_reason       text    not null default '';
alter table teacher_links add column if not exists unlink_requested_at timestamptz;
-- a biometric record can belong to only one approved account
create unique index if not exists one_approved_per_teacher on teacher_links (teacher_id) where status = 'approved';

create table if not exists notices (
  id         bigint generated always as identity primary key,
  title      text not null,
  body       text not null default '',
  faculty    integer,                              -- null = every teacher
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
alter table notices add column if not exists faculty integer;

-- ---------------------------------------------------------------- 5. functions
create function is_app_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from app_admins where user_id = auth.uid())
$$;

create function my_teacher_id() returns integer
language sql stable security definer set search_path = public as $$
  select teacher_id from teacher_links where user_id = auth.uid() and status = 'approved'
$$;

create function my_faculty() returns integer
language sql stable security definer set search_path = public as $$
  select t.faculty from teachers t where t.id = my_teacher_id()
$$;

-- Name search for signing up: only id / name / faculty / position, never the Teacher ID or contact,
-- and hides records already linked to an approved account.
create function search_teachers(q text)
returns table (id integer, name text, faculty integer, "position" text)
language sql stable security definer set search_path = public as $$
  select t.id, t.name, t.faculty, t."position"
  from teachers t
  where auth.uid() is not null
    and not t.deleted
    and length(trim(q)) >= 2
    and position(lower(trim(q)) in lower(t.name)) > 0
    and not exists (select 1 from teacher_links l where l.teacher_id = t.id and l.status = 'approved')
  order by t.name
  limit 25
$$;

-- Dates on which the device has any punches. The phone uses it to tell "absent" from "not downloaded yet".
create function logged_days(p_from date, p_to date)
returns setof date
language sql stable security definer set search_path = public as $$
  select distinct punched_at::date
  from attendance_logs
  where auth.uid() is not null
    and punched_at >= p_from and punched_at < (p_to + 1)
  order by 1
$$;

create function admin_review_link(
  p_id uuid, p_status text,
  p_teacher_id integer default null, p_account_name text default null, p_note text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_app_admin() then raise exception 'Admins only'; end if;
  if p_status not in ('pending','approved','denied') then raise exception 'Bad status'; end if;
  update teacher_links set
    status       = p_status,
    teacher_id   = coalesce(p_teacher_id, teacher_id),
    account_name = coalesce(nullif(trim(p_account_name), ''), account_name),
    admin_note   = coalesce(p_note, admin_note),
    reviewed_at  = now()
  where id = p_id;
end $$;

-- updated_at is bumped so the desktop app picks the change up on its next sync.
create function admin_rename_teacher(p_id integer, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_app_admin() then raise exception 'Admins only'; end if;
  if length(trim(p_name)) = 0 then raise exception 'Name cannot be empty'; end if;
  update teachers set name = trim(p_name), updated_at = now() where id = p_id;
end $$;

-- Sets a shift from the admin phone. 24-hour "HH:mm" PHILIPPINE time; the desktop app
-- downloads it on its next sync and rewrites Employee Form.xls.
create function admin_save_shift(
  p_no integer, p_in1 text, p_out1 text,
  p_in2 text default '', p_out2 text default '', p_ot_in text default '', p_ot_out text default ''
) returns void
language plpgsql security definer set search_path = public as $$
declare
  hm text := '^([01][0-9]|2[0-3]):[0-5][0-9]$';
begin
  if not is_app_admin() then raise exception 'Admins only'; end if;
  if p_no < 1 or p_no > 10 then raise exception 'Shift must be 1 to 10'; end if;
  p_in1 := coalesce(p_in1,''); p_out1 := coalesce(p_out1,''); p_in2 := coalesce(p_in2,''); p_out2 := coalesce(p_out2,'');
  p_ot_in := coalesce(p_ot_in,''); p_ot_out := coalesce(p_ot_out,'');
  if (p_in1 <> '' and p_in1 !~ hm) or (p_out1 <> '' and p_out1 !~ hm) or (p_in2 <> '' and p_in2 !~ hm)
     or (p_out2 <> '' and p_out2 !~ hm) or (p_ot_in <> '' and p_ot_in !~ hm) or (p_ot_out <> '' and p_ot_out !~ hm) then
    raise exception 'Times must be 24-hour HH:mm';
  end if;
  if (p_in1 = '') <> (p_out1 = '') or (p_in2 = '') <> (p_out2 = '') or (p_ot_in = '') <> (p_ot_out = '') then
    raise exception 'Give both the log-in and the log-out time of a period';
  end if;
  if (p_in1 <> '' and p_out1 <= p_in1) or (p_in2 <> '' and p_out2 <= p_in2) or (p_ot_in <> '' and p_ot_out <= p_ot_in) then
    raise exception 'The log-out time must be later than the log-in time';
  end if;
  insert into shifts (no, in1, out1, in2, out2, ot_in, ot_out, updated_at)
  values (p_no, p_in1, p_out1, p_in2, p_out2, p_ot_in, p_ot_out, now())
  on conflict (no) do update set in1 = excluded.in1, out1 = excluded.out1, in2 = excluded.in2,
    out2 = excluded.out2, ot_in = excluded.ot_in, ot_out = excluded.ot_out, updated_at = now();
end $$;

create function request_unlink(p_reason text default '') returns void
language plpgsql security definer set search_path = public as $$
begin
  update teacher_links
     set unlink_requested = true,
         unlink_reason = left(trim(coalesce(p_reason, '')), 300),
         unlink_requested_at = now()
   where user_id = auth.uid() and status = 'approved';
  if not found then raise exception 'You do not have an approved link'; end if;
end $$;

create function cancel_unlink_request() returns void
language plpgsql security definer set search_path = public as $$
begin
  update teacher_links set unlink_requested = false where user_id = auth.uid() and status = 'approved';
end $$;

-- Approve = the link is deleted (the teacher can search and bind again).
-- Decline = the link stays, the flag clears and the note is shown to the teacher.
create function admin_resolve_unlink(p_id uuid, p_approve boolean, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_app_admin() then raise exception 'Admins only'; end if;
  if p_approve then
    delete from teacher_links where id = p_id and unlink_requested;
  else
    update teacher_links
       set unlink_requested = false, admin_note = left(trim(coalesce(p_note, '')), 300), reviewed_at = now()
     where id = p_id and unlink_requested;
  end if;
end $$;

-- ---------------------------------------------------------------- 6. row level security
-- The Render server uses the service-role key and bypasses RLS. The anon key in the apps can only
-- do what these policies allow: a teacher sees their own punches, leaves and notices; an admin sees all.
alter table admins          enable row level security;
alter table teachers        enable row level security;
alter table faculty         enable row level security;
alter table shifts          enable row level security;
alter table leaves          enable row level security;
alter table rules           enable row level security;
alter table attendance_logs enable row level security;
alter table app_admins      enable row level security;   -- no policies: only is_app_admin() reads it
alter table teacher_links   enable row level security;
alter table notices         enable row level security;

create policy links_select on teacher_links for select to authenticated
  using (user_id = auth.uid() or is_app_admin());
create policy links_insert on teacher_links for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');
create policy links_delete on teacher_links for delete to authenticated
  using ((user_id = auth.uid() and status <> 'approved') or is_app_admin());
-- No UPDATE policy: only admins, through admin_review_link().

create policy notices_read on notices for select to authenticated
  using (is_app_admin() or (my_teacher_id() is not null and (faculty is null or faculty = my_faculty())));
create policy notices_admin on notices for all to authenticated
  using (is_app_admin()) with check (is_app_admin());

create policy teachers_self on teachers for select to authenticated
  using (id = my_teacher_id() or is_app_admin());
create policy logs_self on attendance_logs for select to authenticated
  using (teacher_id = my_teacher_id() or is_app_admin());
create policy leaves_self on leaves for select to authenticated
  using (not deleted and (teacher_id = my_teacher_id() or is_app_admin()));

-- Schedule data is not secret; the phone needs it to show "you must log in at 7:50 AM".
create policy faculty_read on faculty for select to authenticated using (true);
create policy shifts_read  on shifts  for select to authenticated using (true);
create policy rules_read   on rules   for select to authenticated using (true);

-- ---------------------------------------------------------------- 7. who may call what
revoke all on function search_teachers(text), logged_days(date,date),
  admin_review_link(uuid,text,integer,text,text), admin_rename_teacher(integer,text),
  admin_save_shift(integer,text,text,text,text,text,text),
  request_unlink(text), cancel_unlink_request(), admin_resolve_unlink(uuid,boolean,text)
  from public, anon;
grant execute on function search_teachers(text), logged_days(date,date),
  admin_review_link(uuid,text,integer,text,text), admin_rename_teacher(integer,text),
  admin_save_shift(integer,text,text,text,text,text,text),
  request_unlink(text), cancel_unlink_request(), admin_resolve_unlink(uuid,boolean,text),
  is_app_admin() to authenticated;

-- ---------------------------------------------------------------- 8. make yourself admin (run separately)
-- 1) Sign up once in the phone app with your email.  2) Run, with your email:
--   insert into app_admins (user_id) select id from auth.users where email = 'you@school.edu';

-- ---------------------------------------------------------------- 9. OPTIONAL clean-up of the old student version
-- Only if this project used to be the student app and you want no student data left. This DELETES data:
--   delete from attendance_logs;              -- old student punches
--   delete from teachers;                     -- (rows that came from the old students table, if any)
--   drop table if exists student_links, students, sections cascade;
