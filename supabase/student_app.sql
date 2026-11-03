-- CNHS Student App: run ONCE in Supabase > SQL Editor, AFTER the existing schema.sql.
-- Students and admins both sign in with Supabase Auth. Everything is protected by
-- row level security, so the anon key shipped in the app can only see what each
-- person is allowed to see.

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
create table if not exists student_links (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  student_id   integer not null references students(id) on delete cascade,
  student_name text not null default '',          -- name the student picked (snapshot)
  account_name text not null default '',          -- name shown for this account (admin can edit)
  email        text not null default '',
  status       text not null default 'pending' check (status in ('pending','approved','denied')),
  admin_note   text not null default '',
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz
);
-- A biometric record can belong to only one approved account.
create unique index if not exists one_approved_per_student
  on student_links (student_id) where status = 'approved';
alter table student_links enable row level security;

create or replace function my_student_id() returns integer
language sql stable security definer set search_path = public as $$
  select student_id from student_links where user_id = auth.uid() and status = 'approved'
$$;

create or replace function my_section() returns integer
language sql stable security definer set search_path = public as $$
  select s.section from students s where s.id = my_student_id()
$$;

drop policy if exists links_select on student_links;
drop policy if exists links_insert on student_links;
drop policy if exists links_delete on student_links;
create policy links_select on student_links for select to authenticated
  using (user_id = auth.uid() or is_app_admin());
create policy links_insert on student_links for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');
create policy links_delete on student_links for delete to authenticated
  using ((user_id = auth.uid() and status <> 'approved') or is_app_admin());
-- No UPDATE policy: only admins, through admin_review_link() below.

-- ---------------------------------------------------------------- notices
create table if not exists notices (
  id         bigint generated always as identity primary key,
  title      text not null,
  body       text not null default '',
  section    integer,                              -- null = everyone
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
alter table notices enable row level security;
drop policy if exists notices_read  on notices;
drop policy if exists notices_admin on notices;
create policy notices_read on notices for select to authenticated
  using (is_app_admin() or (my_student_id() is not null and (section is null or section = my_section())));
create policy notices_admin on notices for all to authenticated
  using (is_app_admin()) with check (is_app_admin());

-- ---------------------------------------------------------------- existing tables
-- (the Render server uses the service-role key and bypasses RLS, so it is unaffected)
drop policy if exists students_self on students;
create policy students_self on students for select to authenticated
  using (id = my_student_id() or is_app_admin());

drop policy if exists logs_self on attendance_logs;
create policy logs_self on attendance_logs for select to authenticated
  using (student_id = my_student_id() or is_app_admin());

drop policy if exists sections_read on sections;
create policy sections_read on sections for select to authenticated using (true);

-- ---------------------------------------------------------------- RPCs
-- Name search for signing up. Returns only id / name / section, never LRN or contact,
-- and hides records that are already linked to an approved account.
create or replace function search_students(q text)
returns table (id integer, name text, section integer)
language sql stable security definer set search_path = public as $$
  select s.id, s.name, s.section
  from students s
  where auth.uid() is not null
    and not s.deleted
    and length(trim(q)) >= 2
    and position(lower(trim(q)) in lower(s.name)) > 0
    and not exists (select 1 from student_links l where l.student_id = s.id and l.status = 'approved')
  order by s.name
  limit 25
$$;

create or replace function admin_review_link(
  p_id uuid, p_status text,
  p_student_id integer default null, p_account_name text default null, p_note text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_app_admin() then raise exception 'Admins only'; end if;
  if p_status not in ('pending','approved','denied') then raise exception 'Bad status'; end if;
  update student_links set
    status       = p_status,
    student_id   = coalesce(p_student_id, student_id),
    account_name = coalesce(nullif(trim(p_account_name), ''), account_name),
    admin_note   = coalesce(p_note, admin_note),
    reviewed_at  = now()
  where id = p_id;
end $$;

-- Renames the student record. updated_at is bumped so the desktop app picks the
-- change up on its next sync and writes it into Employee Form.xls.
create or replace function admin_rename_student(p_id integer, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_app_admin() then raise exception 'Admins only'; end if;
  if length(trim(p_name)) = 0 then raise exception 'Name cannot be empty'; end if;
  update students set name = trim(p_name), updated_at = now() where id = p_id;
end $$;

revoke all on function search_students(text), admin_review_link(uuid,text,integer,text,text),
  admin_rename_student(integer,text) from public, anon;
grant execute on function search_students(text), admin_review_link(uuid,text,integer,text,text),
  admin_rename_student(integer,text), is_app_admin() to authenticated;

-- ---------------------------------------------------------------- make yourself admin
-- 1) Sign up once in the app with your email.  2) Run (with your email):
--   insert into app_admins (user_id) select id from auth.users where email = 'you@school.edu';
