-- =====================================================================
-- First-time setup helpers. Run in Supabase SQL Editor AFTER schema.sql.
-- =====================================================================

-- 1. Create your own account in the app (Create account), then make yourself admin:
update public.profiles set role = 'admin' where email = 'you@eng.ruh.ac.lk';

-- 2. Promote lecturers (they sign up in the app first, like everyone else).
--    Admins can also do this from the app: Home → Users.
-- update public.profiles set role = 'lecturer' where email = 'lecturer@eng.ruh.ac.lk';

-- 3. Optional demo courses owned by a lecturer.
-- insert into public.courses (code, name, semester, lecturer_id)
-- select c.code, c.name, 'Sem 1 2026', p.id
-- from public.profiles p,
--      (values ('EE4305', 'Computer Networks'), ('EE4201', 'Embedded Systems')) as c(code, name)
-- where p.email = 'lecturer@eng.ruh.ac.lk';
