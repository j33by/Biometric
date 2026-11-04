// Starter data for Calape National High School, Grade 12 ABM.
// Built from the school's own device file (Employee Form.xls) and checked against
// the class program photo (adviser: Pulmano, Jeremae T.).
//
// The photo is a class timetable (time x weekday).  The biometric device wants
// the opposite view - one row per TEACHER saying when they must log in and out -
// so each teacher sits in one faculty slot (the device's "Department", named after
// the subject) and the slot's weekly pattern points at one of the shifts:
//
//   Shift 1  7:50 AM –  9:50 AM   Shift 5  4:00 PM – 5:00 PM  (SHS ARAL)
//   Shift 2 10:00 AM – 12:00 PM   Shift 6  7:50 AM – 8:50 AM  (HGP)
//   Shift 3  1:00 PM –  3:00 PM   Shift 7  8:50 AM – 9:50 AM
//   Shift 4  3:00 PM –  4:00 PM
//
// Three things were fixed compared with the file as received (the photo is the
// reference):
//   * Shifts 3, 4 and 5 were stored as 01:00-03:00, 03:00-04:00 and 04:00-05:00.
//     The device reads 24-hour text, so those are 1 AM - 4 AM.  They are now
//     13:00-15:00, 15:00-16:00 and 16:00-17:00.
//   * Shift 6 (HGP) was 07:00-08:50; the photo says 7:50 - 8:50.
//   * Pulmano (ID 8) had no day assigned; the photo gives her Friday 7:50 - 8:50.
//
// Times are Philippine time, 24-hour "HH:mm" exactly as the device file wants.
// "SHS ARAL" (Mon/Tue 4-5 PM) has no teacher named in the photo, so nobody is
// assigned to that slot yet.

import 'models.dart';

class StarterData {
  final List<Teacher> teachers;
  final List<Faculty> faculty;
  final List<Shift> shifts;
  const StarterData(this.teachers, this.faculty, this.shifts);
}

/// Sun..Sat helper: Monday to Friday shift numbers (0 = no duty).
List<int> _week(int mon, int tue, int wed, int thu, int fri) => [0, mon, tue, wed, thu, fri, 0];

/// [stamp] is the updatedAt on every row.  First-run seeding passes an old date so
/// anything an admin already saved in the cloud wins; the "Load starter schedule"
/// button passes the current time so the choice is deliberate and sticks.
StarterData cnhsG12AbmStarter(DateTime stamp) {
  Shift sh(int no, String a, String b) => Shift(no: no, in1: a, out1: b, updatedAt: stamp);

  final shifts = <Shift>[
    sh(1, '07:50', '09:50'),
    sh(2, '10:00', '12:00'),
    sh(3, '13:00', '15:00'),
    sh(4, '15:00', '16:00'),
    sh(5, '16:00', '17:00'),
    sh(6, '07:50', '08:50'),
    sh(7, '08:50', '09:50'),
    for (var i = 8; i <= 10; i++) Shift(no: i, updatedAt: stamp),
  ];

  final faculty = <Faculty>[
    Faculty(no: 1, name: 'Research 12', week: _week(1, 1, 0, 1, 2), updatedAt: stamp),
    Faculty(no: 2, name: 'Pre-Calculus 12', week: _week(2, 4, 3, 3, 7), updatedAt: stamp),
    Faculty(no: 3, name: 'Intro philo 12', week: _week(3, 3, 2, 2, 0), updatedAt: stamp),
    Faculty(no: 4, name: 'Fil Identity 12', week: _week(4, 2, 1, 4, 3), updatedAt: stamp),
    Faculty(no: 5, name: 'SHS ARAL', week: _week(5, 5, 0, 0, 0), updatedAt: stamp),
    Faculty(no: 6, name: 'HGP 12', week: _week(0, 0, 0, 0, 6), updatedAt: stamp),
    // unused slots: named nothing and no duty on any day
    for (var i = 7; i <= 16; i++) Faculty(no: i, name: '', week: List<int>.filled(7, 0), updatedAt: stamp),
  ];

  // Device IDs are the ones already enrolled on the school's device.
  final teachers = <Teacher>[
    Teacher(id: 4, name: 'Mejorada, Daisy G.', faculty: 1, position: 'Teacher', notes: 'Research 12 (G12 ABM)', updatedAt: stamp),
    Teacher(id: 5, name: 'Ruloma, Rosana P.', faculty: 2, position: 'Teacher', notes: 'Pre-Calculus 12 (G12 ABM)', updatedAt: stamp),
    Teacher(id: 6, name: 'Labrador, Alicia C.', faculty: 3, position: 'Teacher', notes: 'Intro to Philosophy 12 (G12 ABM)', updatedAt: stamp),
    Teacher(id: 7, name: 'Sanchez, Ishajane B.', faculty: 4, position: 'Teacher', notes: 'Filipino Identity 12 (G12 ABM)', updatedAt: stamp),
    Teacher(
        id: 8,
        name: 'Pulmano, Jeremae T.',
        faculty: 6,
        position: 'Adviser · G12 ABM',
        notes: 'Homeroom Guidance Program (HGP) 12, class adviser',
        updatedAt: stamp),
  ];

  return StarterData(teachers, faculty, shifts);
}
