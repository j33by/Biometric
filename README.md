# Attendance Console

Windows desktop dashboard (Flutter) for a biometric attendance device that only
exchanges data over USB. The app is the dashboard; the device's own files are
the exchange format.

```
 biometric device ──USB──► Attendance_Logs.txt ──► app ──► Supabase (via Render API)
 biometric device ◄──USB── Employee Form.xls   ◄── app
```

* **Import** – `Attendance_Logs.txt` is picked up automatically from the exchange
  folder or from a USB stick. Each punch is keyed by *student ID + date/time +
  device*, so importing the same file twice (or from two PCs) never duplicates.
* **Export** – `Employee Form.xls` (students, sections, shifts, rules) is rewritten
  after every change. The app edits *the device's own file* in place: formatting,
  the date formulas and sheet protection are preserved byte for byte.
* **Dashboard** – today's attendance, 14-day trend, punches per hour, per-section
  rates, chronic lateness / absence, student history, CSV export.
* **Admins** – cloud accounts with roles (superadmin / admin / viewer).
* Late/early minutes are computed with the same rules as the device report
  (checked against your `All_Report.xls`: 148 min late, 232 min early).

## 1. Supabase (database)
1. Create a project at supabase.com.
2. SQL Editor → paste `supabase/schema.sql` → Run.
3. Project Settings → API: copy the **Project URL** and the **service_role** key
   (keep it secret; it only ever lives on Render).

## 2. Render (server)
1. Push this repo to GitHub.
2. Render → New → **Blueprint** → select the repo (`render.yaml` is picked up).
3. Fill in `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`
   (this creates the first superadmin on first start; `JWT_SECRET` is generated).
4. Wait for deploy; your server address is `https://<name>.onrender.com`.
   The free plan sleeps when idle – the first request can take ~50 s.

## 3. GitHub Actions (Windows build)
Push to `main` (or run the workflow manually). `build-windows.yml` generates the
Windows runner, analyzes, tests, builds, and uploads
`AttendanceConsole-windows.zip` as an artifact. Push a tag like `v1.0.0` to also
attach it to a GitHub Release. Unzip anywhere and run `attendance_console.exe`.

Local build: `flutter create --platforms=windows .` once, then
`flutter pub get && flutter run -d windows`.

## 4. Daily use
1. First launch → enter the Render address and sign in (or *Work offline*).
2. Plug the USB stick that came from the device. Logs import automatically and
   `Employee Form.xls` is written onto the stick.
3. Add/edit students in **Students**; on the device upload the stick's
   `Employee Form.xls`, then enrol the new student's fingerprint under the shown ID.

## Things to know
* **Test the first upload with a backup.** The generated `.xls` was verified with
  two independent readers (xlrd, LibreOffice) and round-trips your file
  cell-for-cell, but not on the physical device. Keep the original file.
* `001_UserInfo.dat` holds fingerprint templates; the app does not touch it.
  Fingerprints can only be enrolled on the device.
* Deleting a row in Excel does not delete the student in the app (deliberate);
  renames/additions made in Excel are merged in.
* Cloud sync is local-first with a 45 s poll, not push-realtime. Offline edits
  queue and flush automatically.
* Server tests: `cd server && npm ci && node test/api.test.js`.
