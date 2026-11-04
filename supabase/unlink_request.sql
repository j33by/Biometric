-- Run ONCE in Supabase > SQL Editor, AFTER teacher_app.sql.
-- Adds "request unlink" for teachers.

-- ---------------------------------------------------------------- unlink requests
alter table teacher_links
  add column if not exists unlink_requested    boolean not null default false,
  add column if not exists unlink_reason       text    not null default '',
  add column if not exists unlink_requested_at timestamptz;

-- Teacher asks to be unlinked from the approved record (wrong person, graduated, new account...).
create or replace function request_unlink(p_reason text default '') returns void
language plpgsql security definer set search_path = public as $$
begin
  update teacher_links
     set unlink_requested = true,
         unlink_reason = left(trim(coalesce(p_reason, '')), 300),
         unlink_requested_at = now()
   where user_id = auth.uid() and status = 'approved';
  if not found then raise exception 'You do not have an approved link'; end if;
end $$;

create or replace function cancel_unlink_request() returns void
language plpgsql security definer set search_path = public as $$
begin
  update teacher_links set unlink_requested = false
   where user_id = auth.uid() and status = 'approved';
end $$;

-- Admin decision. Approve = the link is deleted (the teacher can search and bind again).
-- Decline = the link stays, the flag clears and the note is shown to the teacher.
create or replace function admin_resolve_unlink(p_id uuid, p_approve boolean, p_note text default '') returns void
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

revoke all on function request_unlink(text), cancel_unlink_request(), admin_resolve_unlink(uuid,boolean,text)
  from public, anon;
grant execute on function request_unlink(text), cancel_unlink_request(), admin_resolve_unlink(uuid,boolean,text)
  to authenticated;
