-- OPTIONAL. Pre-loads the Grade 12 ABM class program into Supabase so the phone apps show
-- the schedule even before the desktop app has synced. Safe to run more than once:
-- `on conflict do nothing`, and the old updated_at means anything saved later wins.
-- Run after schema.sql. Times are Philippine time, 24-hour.

insert into shifts (no, in1, out1, updated_at) values
  (1,'07:50','09:50','2026-01-01'),
  (2,'10:00','12:00','2026-01-01'),
  (3,'13:00','15:00','2026-01-01'),
  (4,'15:00','16:00','2026-01-01'),
  (5,'16:00','17:00','2026-01-01'),   -- SHS ARAL
  (6,'07:50','08:50','2026-01-01'),   -- HGP
  (7,'08:50','09:50','2026-01-01')
on conflict (no) do nothing;
insert into shifts (no, updated_at) select g, '2026-01-01' from generate_series(8,10) g on conflict (no) do nothing;

-- week = Sunday..Saturday shift numbers (0 = no duty)
insert into faculty (no, name, week, updated_at) values
  (1,'Research 12',    '[0,1,1,0,1,2,0]','2026-01-01'),
  (2,'Pre-Calculus 12','[0,2,4,3,3,7,0]','2026-01-01'),
  (3,'Intro philo 12', '[0,3,3,2,2,0,0]','2026-01-01'),
  (4,'Fil Identity 12','[0,4,2,1,4,3,0]','2026-01-01'),
  (5,'SHS ARAL',       '[0,5,5,0,0,0,0]','2026-01-01'),
  (6,'HGP 12',         '[0,0,0,0,0,6,0]','2026-01-01')
on conflict (no) do nothing;
insert into faculty (no, name, week, updated_at) select g, '', '[0,0,0,0,0,0,0]', '2026-01-01' from generate_series(7,16) g on conflict (no) do nothing;

insert into teachers (id, name, faculty, position, notes, updated_at) values
  (4,'Mejorada, Daisy G.',  1,'Teacher','Research 12 (G12 ABM)','2026-01-01'),
  (5,'Ruloma, Rosana P.',   2,'Teacher','Pre-Calculus 12 (G12 ABM)','2026-01-01'),
  (6,'Labrador, Alicia C.', 3,'Teacher','Intro to Philosophy 12 (G12 ABM)','2026-01-01'),
  (7,'Sanchez, Ishajane B.',4,'Teacher','Filipino Identity 12 (G12 ABM)','2026-01-01'),
  (8,'Pulmano, Jeremae T.', 6,'Adviser · G12 ABM','Homeroom Guidance Program (HGP) 12, class adviser','2026-01-01')
on conflict (id) do nothing;

insert into rules (id, company, updated_at) values (1, 'Calape National High School', '2026-01-01')
on conflict (id) do nothing;
