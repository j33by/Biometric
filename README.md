# CNHS Teachers Attendance

Calape National High School · teacher log-ins and log-outs from a biometric device that
only exchanges data over USB. Three parts that share one Supabase database:

| Part | What it is | Who uses it |
|---|---|---|
| **Desktop app** (this folder, Flutter / Windows) | The dashboard. Imports the device's punches, writes the device's `Employee Form.xls`, manages teachers, faculty schedules, shifts and leaves. | The school office |
| **Teacher / Admin phone app** (`teacher_app/`, Flutter / Android) | Teachers see their own schedule, log-ins/outs and attendance. Admins see who is in, edit shift times and approve accounts. | Teachers, admins |
| **Server** (`server/`, Node on Render) | API between the desktop app and Supabase. | – |

```
 biometric device ──USB──► Attendance_Logs.txt ──► desktop app ──► Render API ──► Supabase ──► phones
 biometric device ◄──USB── Employee Form.xls   ◄── desktop app
```

## How a teacher's day is decided

* Each teacher belongs to one **faculty slot** (the device's 16 "Department" slots). The slot is
  **named after the subject** they teach and holds a weekly pattern: which **shift** applies on
  Monday … Sunday.
* A **shift** is the log-in and log-out time (e.g. 7:50 AM – 9:50 AM), in **Philippine time**.
* First punch of the day = **log-in**, last punch = **log-out**. Late = log-in after the shift start
  (minus the late allowance), early out = log-out before the shift end.
* A scheduled day with no punch is **absent** only if the device has data for that day; otherwise it
  is "no data" (the device simply was not downloaded). A **leave** turns an absence into "on leave".
* In the app the slot is called **Faculty** / **Subject**. In the Excel file it stays **Department**,
  because that is the column the device reads.

### The Grade 12 ABM program (from the class program photo)
| Device ID | Teacher | Subject (slot) | Mon | Tue | Wed | Thu | Fri |
|---|---|---|---|---|---|---|---|
| 4 | Mejorada, Daisy G. | Research 12 (1) | 7:50–9:50 AM | 7:50–9:50 AM | – | 7:50–9:50 AM | 10:00 AM–12:00 PM |
| 5 | Ruloma, Rosana P. | Pre-Calculus 12 (2) | 10:00 AM–12:00 PM | 3:00–4:00 PM | 1:00–3:00 PM | 1:00–3:00 PM | 8:50–9:50 AM |
| 6 | Labrador, Alicia C. | Intro philo 12 (3) | 1:00–3:00 PM | 1:00–3:00 PM | 10:00 AM–12:00 PM | 10:00 AM–12:00 PM | – |
| 7 | Sanchez, Ishajane B. | Fil Identity 12 (4) | 3:00–4:00 PM | 10:00 AM–12:00 PM | 7:50–9:50 AM | 3:00–4:00 PM | 1:00–3:00 PM |
| 8 | Pulmano, Jeremae T. (adviser) | HGP 12 (6) | – | – | – | – | 7:50–8:50 AM |

"SHS ARAL" (Mon/Tue 4:00–5:00 PM, slot 5, shift 5) has no teacher in the photo, so nobody is assigned.
It is loaded automatically on first run, or with **Faculty & shifts → Load G12 ABM program**.

> **Fixed compared with the `Employee Form.xls` you sent.** The device reads 24-hour text, but shifts 3, 4
> and 5 were saved as `01:00–03:00`, `03:00–04:00`, `04:00–05:00` (1 AM–4 AM), so every afternoon class
> would have shown as absent. They are now `13:00–15:00`, `15:00–16:00`, `16:00–17:00`. HGP's shift was
> `07:00–08:50` (photo: 7:50) and Pulmano had no day assigned (photo: Friday). Teachers 1–3 (abc, Panel 1,
> Merry Joy Villorejo) are on the Research 12 schedule in your file, so they will show **absent** on
> Mon/Tue/Thu/Fri: remove them or move them to an unused faculty slot.

## Philippine time (so the app and the device never disagree)
* Shift times are typed in the app as **7:50 AM / 1:00 PM / 13:00** and always saved as 24-hour `HH:mm`,
  exactly what the device file holds. The editor warns about odd hours (the "1:00 means 1 AM" mistake).
* "Now" and "today" come from the real UTC time **+ 8 h**, never from the zone of the PC, phone or
  server (Render and Supabase run on UTC). A small globe icon appears in the desktop title bar if the
  PC is on another zone, and nothing breaks.
* **Device clock** (Device sync page): type the time the device screen shows; the app works out how far
  off it is and can add a correction to every imported punch. Importing punches from the future raises a
  warning. Best fix: set the clock on the device, keep the correction at 0.
* Server `/api/health` reports Philippine time; the desktop app can compare the PC against it.

## Desktop app features
* **Dashboard** – present / late / absent / on leave, **On duty now** (who should be in school at this
  minute and whether they have logged in), 14-day trend, punches by hour, per-subject rates, most late,
  most absent, latest punches.
* **Teachers** – device ID, name, **Teacher ID** (employee number, unique), position, subject, role on the
  device, contact, notes. Detail view: weekly log-in/out times, month totals, **Export DTR** (Daily Time Record CSV).
* **Attendance** – a day per teacher with the scheduled time, log-in, log-out, late, early out; filters;
  raw punches; **Export day** and **Export month** (CSV).
* **Leaves** – sick, vacation, official business, training, personal, other; date ranges.
* **Faculty & shifts** – the 16 slots (subject + weekday pattern) and the 10 shifts; attendance rules.
* **Device sync** – USB import/export, device clock, cloud sync.
* **Administrators** – cloud accounts (superadmin / admin / viewer).

## Setup
1. **Supabase**: SQL Editor → paste **`supabase/setup_all.sql`** → Run. That one file is everything. It works on a
   new project, on a project that already has the old student version, and on one where an earlier attempt
   stopped half way, and it is safe to run again. (`schema.sql`, `teacher_app.sql`, `unlink_request.sql` and
   `migrate_from_student_version.sql` are the same thing in pieces, kept for reference. Do not run them on top of it.)
   Optional: `supabase/seed_cnhs_g12_abm.sql` pre-loads the program above. Then make yourself admin (last lines of `setup_all.sql`).
2. **Render**: New → Blueprint → this repo; fill `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `ADMIN_EMAIL`,
   `ADMIN_PASSWORD`.
3. **Desktop app**: GitHub Actions → *Build Windows app* → download `AttendanceConsole-windows.zip`
   (tag `v2.0.0` to publish a release). Local: `flutter create --platforms=windows .` then `flutter run -d windows`.
4. **Phone app**: see `teacher_app/README.md` (tag `teacher-v2.0.0` for an APK release).

An existing desktop database (`db.json` from the student version) is upgraded automatically: students become
teachers, sections become faculty slots, and pending sync entries are kept.

## Daily use
1. Plug in the USB stick from the device. Punches import automatically; `Employee Form.xls` is written onto it.
2. New teacher: **Teachers → Add teacher**, upload the stick's `Employee Form.xls` to the device, enrol the
   fingerprint under the shown device ID.
3. Changing a class time: **Faculty & shifts → edit shift** (or from the admin phone app, Schedule tab), then upload
   `Employee Form.xls` to the device again.

## Things to know
* **Test the first upload with a backup of the device's original file.** The generated `.xls` round-trips your
  file cell for cell and was checked with independent readers, but not on the physical device.
* `001_UserInfo.dat` holds fingerprint templates; the app never touches it.
* Punches reach the phones only after the office imports the device (the device has no network), so "Absent"
  and "Late" appear after the download, not in real time.
* Cloud sync is local-first with a 45 s poll; offline edits queue and flush automatically.
* Tests: `flutter test` (desktop core), `cd server && npm ci && npm test`, `cd teacher_app && flutter test`.
  `tools/check_shared.sh` keeps `schedule_calc.dart` identical in both apps.
