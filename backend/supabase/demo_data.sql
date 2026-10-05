-- =====================================================================
-- DEMO DATA — 2 courses, 20 students, 8 past sessions per course.
-- Run in Supabase SQL Editor AFTER schema.sql and AFTER you have created
-- your admin/lecturer account in the app.
--
-- 1. Change the email on the line marked  <-- YOUR EMAIL
-- 2. Run. Running it twice does nothing the second time.
-- 3. To remove it later, run the CLEANUP block at the bottom.
--
-- Fingerprint templates here are random bytes: they work with the app's
-- "demo device" but NOT with the real sensor. Delete them before using
-- real hardware (see CLEANUP).
-- =====================================================================

do $$
declare
  v_email    text := 'srivaxshana1604@gmail.com';   -- <-- YOUR EMAIL
  v_lecturer uuid;
  v_session  uuid;
  v_start    timestamptz;
  c          record;
  i          int;
  names text[] := array[
    'A. Nishanthan', 'S. Kavindi', 'M. Rizwan', 'K. Tharshan', 'D. Fernando',
    'R. Mathusan', 'H. Silva', 'N. Ahamed', 'P. Jayasuriya', 'T. Perera',
    'J. Wickramasinghe', 'V. Sivakumar', 'L. Bandara', 'F. Hameed', 'C. Rathnayake',
    'G. Kugathasan', 'I. Senanayake', 'Y. Dissanayake', 'U. Rajapaksha', 'B. Gunawardena'];
begin
  select id into v_lecturer from public.profiles where email = v_email;
  if v_lecturer is null then
    raise exception 'No account for %. Create it in the app first, or fix the email at the top.', v_email;
  end if;

  if exists (select 1 from public.sessions where device_id = 'DEMO') then
    raise notice 'Demo data already loaded — nothing to do.';
    return;
  end if;

  -- Courses
  insert into public.courses (code, name, semester, lecturer_id) values
    ('EE4305', 'Computer Networks', 'Semester 7 - 2026', v_lecturer),
    ('EE4201', 'Embedded Systems',  'Semester 7 - 2026', v_lecturer)
  on conflict (code) do nothing;

  -- Students EG/2023/5401 … EG/2023/5420
  for i in 1..20 loop
    insert into public.students (reg_no, full_name, batch)
    values (format('EG/2023/%s', 5400 + i), names[i], 'E23')
    on conflict (reg_no) do nothing;
  end loop;

  -- Fingerprints for 18 students (5419 and 5420 left without, to show "No fingerprint")
  insert into public.fingerprints (student_id, template, device_id, enrolled_by)
  select s.id,
         encode(decode(repeat(md5(random()::text), 32), 'hex'), 'base64'),  -- 512 random bytes
         'DEMO', v_lecturer
  from public.students s
  where s.reg_no between 'EG/2023/5401' and 'EG/2023/5418'
  on conflict (student_id) do nothing;
  update public.fingerprints set template = replace(template, E'\n', '') where device_id = 'DEMO';

  -- Everyone takes both courses
  insert into public.course_students (course_id, student_id)
  select co.id, s.id
  from public.courses co cross join public.students s
  where co.code in ('EE4305', 'EE4201') and s.reg_no between 'EG/2023/5401' and 'EG/2023/5420'
  on conflict do nothing;

  -- 8 weekly past sessions per course, with realistic attendance
  for c in select id, code from public.courses where code in ('EE4305', 'EE4201') loop
    for i in 1..8 loop
      v_start := date_trunc('day', now()) - make_interval(days => 7 * i)
               + case when c.code = 'EE4305' then interval '10 hours 15 minutes' else interval '8 hours' end;

      insert into public.sessions (course_id, session_type, started_at, ended_at, late_after_min, status, created_by, device_id)
      values (c.id, case when i % 3 = 0 then 'lab' else 'lecture' end,
              v_start, v_start + interval '2 hours', 15, 'closed', v_lecturer, 'DEMO')
      returning id into v_session;

      insert into public.attendance (session_id, student_id, status, checked_at, method, device_id)
      select v_session, x.id, x.st,
             case x.st
               when 'present' then v_start + random() * interval '12 minutes'
               when 'late'    then v_start + interval '18 minutes' + random() * interval '20 minutes'
             end,
             case when x.st = 'absent' then 'auto' when x.has_fp then 'fingerprint' else 'manual' end,
             case when x.st = 'absent' then null else 'DEMO' end
      from (
        select st.id, st.fingerprint_enrolled_at is not null as has_fp,
               case when r < p then 'present' when r < p + 0.06 then 'late' else 'absent' end as st
        from (
          select s.id, s.fingerprint_enrolled_at, random() as r,
                 case s.reg_no                       -- a few students with low attendance
                   when 'EG/2023/5403' then 0.50
                   when 'EG/2023/5409' then 0.65
                   when 'EG/2023/5419' then 0.70
                   else 0.88
                 end as p
          from public.course_students cs
          join public.students s on s.id = cs.student_id
          where cs.course_id = c.id
        ) st
      ) x;
    end loop;
  end loop;

  raise notice 'Demo data loaded: 2 courses, 20 students, 16 sessions.';
end $$;


-- =====================================================================
-- CLEANUP — select these lines and run them to remove the demo data.
-- (Keeps students who linked an app account, and keeps the courses.)
-- =====================================================================
-- delete from public.sessions where device_id = 'DEMO';
-- delete from public.fingerprints where device_id = 'DEMO';
-- delete from public.students where reg_no between 'EG/2023/5401' and 'EG/2023/5420' and user_id is null;
