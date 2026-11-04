-- NOTE: superseded by setup_all.sql (one safe, re-runnable file). Kept for reference; do not run it on top of setup_all.sql.
-- ONLY for a Supabase project that already ran the old STUDENT version of this system.
-- (A brand-new project skips this file: schema.sql + teacher_app.sql are enough.)
-- Run ONCE in the SQL Editor, BEFORE teacher_app.sql. It renames in place, so nothing
-- is lost, but the rows are still the old student records: delete them afterwards if
-- you want to start clean (see the last lines).

-- tables
alter table if exists students      rename to teachers;
alter table if exists sections      rename to faculty;
alter table if exists student_links rename to teacher_links;

-- columns
do $$ begin
  if exists (select 1 from information_schema.columns where table_name='teachers' and column_name='section') then
    alter table teachers rename column section to faculty;
  end if;
  if exists (select 1 from information_schema.columns where table_name='teachers' and column_name='lrn') then
    alter table teachers rename column lrn to teacher_no;
  end if;
  if exists (select 1 from information_schema.columns where table_name='attendance_logs' and column_name='student_id') then
    alter table attendance_logs rename column student_id to teacher_id;
  end if;
  if exists (select 1 from information_schema.columns where table_name='teacher_links' and column_name='student_id') then
    alter table teacher_links rename column student_id to teacher_id;
  end if;
  if exists (select 1 from information_schema.columns where table_name='teacher_links' and column_name='student_name') then
    alter table teacher_links rename column student_name to teacher_name;
  end if;
  if exists (select 1 from information_schema.columns where table_name='notices' and column_name='section') then
    alter table notices rename column section to faculty;
  end if;
end $$;

alter table teachers add column if not exists position text not null default '';
alter table rules    add column if not exists clock_offset_min integer not null default 0;
alter table faculty  alter column week set default '[0,1,1,1,1,1,0]';

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
alter table leaves enable row level security;

alter index if exists one_approved_per_student rename to one_approved_per_teacher;

-- old helper functions (teacher_app.sql creates the new ones)
drop function if exists my_student_id();
drop function if exists my_section();
drop function if exists search_students(text);
drop function if exists admin_rename_student(integer, text);
drop policy if exists students_self on teachers;
drop policy if exists sections_read on faculty;

-- To start with no old student rows (optional):
--   delete from attendance_logs; delete from teacher_links; delete from teachers; delete from notices;
