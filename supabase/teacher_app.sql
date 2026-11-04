-- NOTE: superseded by setup_all.sql (one safe, re-runnable file). Kept for reference; do not run it on top of setup_all.sql.
-- CNHS Teacher App: run ONCE in Supabase > SQL Editor, AFTER schema.sql
-- (or after migrate_from_student_version.sql on an older project).
-- Teachers and admins both sign in with Supabase Auth. Everything is protected by
-- row level security, so the anon key shipped in the app can only see what each
-- person is allowed to see: a teacher sees their own punches, leaves and notices;
-- an admin sees everyone.
-- All wall-clock values are Philippine time (UTC+8), see schema.sql.

-- ---------------------------------------------------------------- admins
create table if not exists app_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table app_admins enable row level security;   -- no policies: only is_app_admin() reads it

create or replace function is_app_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from app_admins where user_id = auth.uid())
$$;

-- ---------------------------------------------------------------- links
-- A teacher's phone account is bound to ONE biometric record (device ID) after an admin approves.
create table if not exists teacher_links (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  teacher_id   integer not null references teachers(id) on delete cascade,
  teacher_name text not null default '',          -- name the teacher picked (snapshot)
  account_name text not null default '',          -- name shown for this account (admin can edit)
  email        text not null default '',
  status       text not null default 'pending' check (status in ('pending','approved','denied')),
  admin_note   text not null default '',
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz
);
-- A biometric record can belong to only one approved account.
create unique index if not exists one_approved_per_teacher
  on teacher_links (teacher_id) where status = 'approved';
alter table teacher_links enable row level security;

create or replace function my_teacher_id() returns integer
language sql stable security definer set search_path = public as $$
  select teacher_id from teacher_links where user_id = auth.uid() and status = 'approved'
$$;

create or replace function my_faculty() returns integer
language sql stable security definer set search_path = public as $$
  select t.faculty from teachers t where t.id = my_teacher_id()
$$;

drop policy if exists links_select on teacher_links;
drop policy if exists links_insert on teacher_links;
drop policy if exists links_delete on teacher_links;
create policy links_select on teacher_links for select to authenticated
  using (user_id = auth.uid() or is_app_admin());
create policy links_insert on teacher_links for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');
create policy links_delete on teacher_links for delete to authenticated
  using ((user_id = auth.uid() and status <> 'approved') or is_app_admin());
-- No UPDATE policy: only admins, through admin_review_link() below.

-- ---------------------------------------------------------------- notices
create table if not exists notices (
  id         bigint generated always as identity primary key,
  title      text not null,
  body       text not null default '',
  faculty    integer,                              -- null = every teacher
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
alter table notices enable row level security;
drop policy if exists notices_read  on notices;
drop policy if exists notices_admin on notices;
create policy notices_read on notices for select to authenticated
  using (is_app_admin() or (my_teacher_id() is not null and (faculty is null or faculty = my_faculty())));
create policy notices_admin on notices for all to authenticated
  using (is_app_admin()) with check (is_app_admin());

-- ---------------------------------------------------------------- existing tables
-- (the Render server uses the service-role key and bypasses RLS, so it is unaffected)
drop policy if exists teachers_self on teachers;
create policy teachers_self on teachers for select to authenticated
  using (id = my_teacher_id() or is_app_admin());

drop policy if exists logs_self on attendance_logs;
create policy logs_self on attendance_logs for select to authenticated
  using (teacher_id = my_teacher_id() or is_app_admin());

-- Schedule data is not secret and the phone needs it to show "you must log in at 7:50 AM".
drop policy if exists faculty_read on faculty;
create policy faculty_read on faculty for select to authenticated using (true);
drop policy if exists shifts_read on shifts;
create policy shifts_read on shifts for select to authenticated using (true);
drop policy if exists rules_read on rules;
create policy rules_read on rules for select to authenticated using (true);

drop policy if exists leaves_self on leaves;
create policy leaves_self on leaves for select to authenticated
  using (not deleted and (teacher_id = my_teacher_id() or is_app_admin()));

-- ---------------------------------------------------------------- RPCs
-- Name search for signing up. Returns only id / name / faculty / position, never the
-- Teacher ID or contact, and hides records already linked to an approved account.
create or replace function search_teachers(q text)
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

-- Dates (in a range) on which the device has any punches at all. The phone uses it to tell
-- "absent" from "the device was not downloaded that day".
create or replace function logged_days(p_from date, p_to date)
returns setof date
language sql stable security definer set search_path = public as $$
  select distinct punched_at::date
  from attendance_logs
  where auth.uid() is not null
    and punched_at >= p_from and punched_at < (p_to + 1)
  order by 1
$$;

create or replace function admin_review_link(
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

-- Renames the teacher record. updated_at is bumped so the desktop app picks the
-- change up on its next sync and writes it into Employee Form.xls.
create or replace function admin_rename_teacher(p_id integer, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_app_admin() then raise exception 'Admins only'; end if;
  if length(trim(p_name)) = 0 then raise exception 'Name cannot be empty'; end if;
  update teachers set name = trim(p_name), updated_at = now() where id = p_id;
end $$;

-- Sets a shift's log-in / log-out times from the admin phone. Times are 24-hour "HH:mm"
-- PHILIPPINE time (the app converts what the admin types). updated_at is bumped so the
-- desktop app downloads it and rewrites Employee Form.xls for the device.
create or replace function admin_save_shift(
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

revoke all on function search_teachers(text), logged_days(date,date),
  admin_review_link(uuid,text,integer,text,text), admin_rename_teacher(integer,text),
  admin_save_shift(integer,text,text,text,text,text,text) from public, anon;
grant execute on function search_teachers(text), logged_days(date,date),
  admin_review_link(uuid,text,integer,text,text), admin_rename_teacher(integer,text),
  admin_save_shift(integer,text,text,text,text,text,text), is_app_admin() to authenticated;

-- ---------------------------------------------------------------- make yourself admin
-- 1) Sign up once in the app with your email.  2) Run (with your email):
--   insert into app_admins (user_id) select id from auth.users where email = 'you@school.edu';
