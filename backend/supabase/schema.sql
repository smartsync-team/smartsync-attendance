-- =====================================================================
-- Fingerprint + QR Attendance System — database schema
-- Paste this whole file into Supabase Dashboard → SQL Editor → Run.
-- Safe to run once on a fresh project.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Users / roles
-- ---------------------------------------------------------------------
create type public.user_role as enum ('student', 'lecturer', 'admin');

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text not null default '',
  role        public.user_role not null default 'student',
  created_at  timestamptz not null default now()
);

-- Every new sign-up gets a profile with role 'student'.
-- Lecturers/admins are promoted afterwards (see seed.sql or the in-app Users screen).
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Core tables
-- ---------------------------------------------------------------------
create table public.courses (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  name         text not null,
  semester     text,
  lecturer_id  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);

create table public.students (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid unique references public.profiles (id) on delete set null,
  reg_no                   text not null unique,
  full_name                text not null,
  batch                    text,
  fingerprint_enrolled_at  timestamptz,   -- maintained by trigger on fingerprints
  created_at               timestamptz not null default now()
);

create table public.course_students (
  course_id   uuid not null references public.courses (id) on delete cascade,
  student_id  uuid not null references public.students (id) on delete cascade,
  joined_at   timestamptz not null default now(),
  primary key (course_id, student_id)
);
create index course_students_student_idx on public.course_students (student_id);

-- Fingerprint templates live here, not permanently on the sensor.
-- A sensor holds ~200–1000 templates, so before each session the app loads
-- only that course's students onto the device.
create table public.fingerprints (
  student_id   uuid primary key references public.students (id) on delete cascade,
  template     text not null,           -- base64 of the 512-byte sensor template
  device_id    text,
  enrolled_by  uuid references public.profiles (id) on delete set null,
  enrolled_at  timestamptz not null default now()
);

create table public.sessions (
  id              uuid primary key default gen_random_uuid(),
  course_id       uuid not null references public.courses (id) on delete cascade,
  session_type    text not null default 'lecture'
                  check (session_type in ('lecture', 'lab', 'tutorial')),
  started_at      timestamptz not null default now(),
  ended_at        timestamptz,
  late_after_min  int not null default 15,
  status          text not null default 'open' check (status in ('open', 'closed')),
  device_id       text,
  created_by      uuid references public.profiles (id) on delete set null
);
create index sessions_course_idx on public.sessions (course_id, started_at desc);

create table public.attendance (
  id          bigint generated always as identity primary key,
  session_id  uuid not null references public.sessions (id) on delete cascade,
  student_id  uuid not null references public.students (id) on delete cascade,
  status      text not null check (status in ('present', 'late', 'absent')),
  checked_at  timestamptz,
  method      text not null default 'fingerprint'
              check (method in ('fingerprint', 'manual', 'auto')),
  device_id   text,
  unique (session_id, student_id)
);
create index attendance_student_idx on public.attendance (student_id);

-- Keep students.fingerprint_enrolled_at in sync so students can see their
-- status without being able to read the template itself.
create function public.sync_fingerprint_flag() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    update public.students set fingerprint_enrolled_at = null where id = old.student_id;
    return old;
  end if;
  update public.students set fingerprint_enrolled_at = new.enrolled_at where id = new.student_id;
  return new;
end $$;

create trigger fingerprints_flag
  after insert or update or delete on public.fingerprints
  for each row execute function public.sync_fingerprint_flag();

-- ---------------------------------------------------------------------
-- Helper functions used by RLS policies
-- ---------------------------------------------------------------------
create function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('lecturer', 'admin') from public.profiles where id = auth.uid()),
    false)
$$;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false)
$$;

create function public.my_student_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.students where user_id = auth.uid()
$$;

-- The course's lecturer or any admin may run sessions for it.
create function public.can_manage_course(p_course_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or exists (select 1 from public.courses
                 where id = p_course_id and lecturer_id = auth.uid())
$$;

create function public.can_manage_session(p_session_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.can_manage_course((select course_id from public.sessions where id = p_session_id))
$$;

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.courses         enable row level security;
alter table public.students        enable row level security;
alter table public.course_students enable row level security;
alter table public.fingerprints    enable row level security;
alter table public.sessions        enable row level security;
alter table public.attendance      enable row level security;

-- profiles
create policy "read own or staff" on public.profiles
  for select using (id = auth.uid() or public.is_staff());
create policy "admin updates roles" on public.profiles
  for update using (public.is_admin()) with check (public.is_admin());

-- courses: everyone signed in can see the course list (needed to join by code)
create policy "read courses" on public.courses
  for select to authenticated using (true);
create policy "staff create courses" on public.courses
  for insert with check (public.is_staff() and (lecturer_id = auth.uid() or public.is_admin()));
create policy "owner updates course" on public.courses
  for update using (public.can_manage_course(id));
create policy "owner deletes course" on public.courses
  for delete using (public.can_manage_course(id));

-- students
create policy "read own or staff" on public.students
  for select using (user_id = auth.uid() or public.is_staff());
create policy "staff insert students" on public.students
  for insert with check (public.is_staff());
create policy "staff update students" on public.students
  for update using (public.is_staff());
create policy "admin delete students" on public.students
  for delete using (public.is_admin());

-- course_students
create policy "read own or staff" on public.course_students
  for select using (student_id = public.my_student_id() or public.is_staff());
create policy "staff add to course" on public.course_students
  for insert with check (public.is_staff());
create policy "staff remove from course" on public.course_students
  for delete using (public.can_manage_course(course_id));

-- fingerprints: biometric data, staff only
create policy "staff only" on public.fingerprints
  for all using (public.is_staff()) with check (public.is_staff());

-- sessions
create policy "read sessions" on public.sessions
  for select using (
    public.is_staff()
    or exists (select 1 from public.course_students cs
               where cs.course_id = sessions.course_id
                 and cs.student_id = public.my_student_id()));
create policy "manager creates session" on public.sessions
  for insert with check (public.can_manage_course(course_id) and created_by = auth.uid());
create policy "manager updates session" on public.sessions
  for update using (public.can_manage_course(course_id));

-- attendance
create policy "read own or staff" on public.attendance
  for select using (student_id = public.my_student_id() or public.is_staff());
create policy "manager writes attendance" on public.attendance
  for insert with check (public.can_manage_session(session_id));
create policy "manager updates attendance" on public.attendance
  for update using (public.can_manage_session(session_id));

-- ---------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------

-- Student self-registration from the app (after scanning a course QR).
-- Creates the student record (or claims one a lecturer created manually
-- that has no app account yet) and joins the course.
create function public.register_student(
  p_reg_no text, p_full_name text, p_batch text, p_course_id uuid default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_existing record;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  p_reg_no := upper(trim(p_reg_no));
  if p_reg_no = '' or trim(p_full_name) = '' then
    raise exception 'Registration number and name are required';
  end if;

  select id into v_id from students where user_id = v_uid;
  if v_id is not null then
    if (select reg_no from students where id = v_id) <> p_reg_no then
      raise exception 'Your account is already linked to another registration number';
    end if;
    update students set full_name = trim(p_full_name), batch = nullif(trim(p_batch), '')
      where id = v_id;
  else
    select id, user_id into v_existing from students where reg_no = p_reg_no;
    if v_existing.id is not null then
      if v_existing.user_id is not null then
        raise exception 'This registration number is already linked to another account';
      end if;
      update students
        set user_id = v_uid, full_name = trim(p_full_name), batch = nullif(trim(p_batch), '')
        where id = v_existing.id;
      v_id := v_existing.id;
    else
      insert into students (user_id, reg_no, full_name, batch)
        values (v_uid, p_reg_no, trim(p_full_name), nullif(trim(p_batch), ''))
        returning id into v_id;
    end if;
  end if;

  update profiles set full_name = trim(p_full_name) where id = v_uid;

  if p_course_id is not null then
    insert into course_students (course_id, student_id) values (p_course_id, v_id)
      on conflict do nothing;
  end if;
  return v_id;
end $$;

-- Already-registered student joins another course.
create function public.join_course(p_course_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_id uuid := public.my_student_id();
begin
  if v_id is null then raise exception 'Complete your student registration first'; end if;
  insert into course_students (course_id, student_id) values (p_course_id, v_id)
    on conflict do nothing;
end $$;

-- Close a session: everyone in the course who was not marked becomes absent.
create function public.close_session(p_session_id uuid, p_ended_at timestamptz default now())
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_course uuid;
  v_absent int;
begin
  if not public.can_manage_session(p_session_id) then
    raise exception 'Not allowed to close this session';
  end if;
  select course_id into v_course from sessions where id = p_session_id;

  insert into attendance (session_id, student_id, status, method)
    select p_session_id, cs.student_id, 'absent', 'auto'
    from course_students cs
    where cs.course_id = v_course
      and not exists (select 1 from attendance a
                      where a.session_id = p_session_id and a.student_id = cs.student_id)
    on conflict (session_id, student_id) do nothing;
  get diagnostics v_absent = row_count;

  update sessions
    set status = 'closed', ended_at = coalesce(ended_at, p_ended_at)
    where id = p_session_id;

  return json_build_object('absent_marked', v_absent);
end $$;

-- ---------------------------------------------------------------------
-- Reporting views (security_invoker → RLS of the caller applies)
-- ---------------------------------------------------------------------
create view public.session_stats with (security_invoker = true) as
select
  s.id as session_id, s.course_id, s.session_type, s.started_at, s.ended_at, s.status,
  count(a.id) filter (where a.status in ('present', 'late')) as attended,
  count(a.id) filter (where a.status = 'late')               as late,
  (select count(*) from public.course_students cs where cs.course_id = s.course_id) as enrolled
from public.sessions s
left join public.attendance a on a.session_id = s.id
group by s.id;

create view public.student_course_summary with (security_invoker = true) as
select
  cs.course_id, cs.student_id, st.reg_no, st.full_name,
  (st.fingerprint_enrolled_at is not null) as has_fingerprint,
  count(se.id) filter (where se.status = 'closed') as sessions_held,
  count(a.id)  filter (where se.status = 'closed' and a.status in ('present', 'late')) as attended,
  case when count(se.id) filter (where se.status = 'closed') = 0 then null
       else round(100.0 * count(a.id) filter (where se.status = 'closed' and a.status in ('present', 'late'))
                  / count(se.id) filter (where se.status = 'closed'), 1)
  end as percent
from public.course_students cs
join public.students st on st.id = cs.student_id
left join public.sessions se on se.course_id = cs.course_id
left join public.attendance a on a.session_id = se.id and a.student_id = cs.student_id
group by cs.course_id, cs.student_id, st.reg_no, st.full_name, st.fingerprint_enrolled_at;
