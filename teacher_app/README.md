# CNHS Teacher App

Flutter app (Android / iOS / web) for **teachers** and **admins**. It talks to the same Supabase project as
the desktop app, protected by row level security. All times are **Philippine time (UTC+8)**, whatever zone the
phone is set to.

## Teachers
1. Sign up (Google, or email + password) and search your name.
2. Pick the biometric record and send a request. Nothing is visible until an admin approves it.
3. Once approved:
   * **Home** – a live Philippine clock, *today's duty* ("You must be in school 7:50 – 9:50 AM"), what to do
     next ("Log in at 7:50 AM · in 25 min", "Log out after 9:50 AM"), your log-in / log-out, and your
     **weekly schedule**.
   * **Attendance** – month calendar coloured by status (present, late, absent, on leave), totals and total
     late minutes, tap a day for the details.
   * **Logs** – **your own punches** for the last 14 / 30 / 60 days, day by day, each marked *Log in* /
     *Log out* with the scheduled time, late minutes, "no log-out" and leave days.
   * **Notices** – everyone, or just your subject.
   * **Profile** – device ID, **Teacher ID**, subject, position; request unlink.

Punches appear after the school office downloads the device. A scheduled day only turns **Absent** once the
device log for that day exists; until then it shows *Not synced*.

## Admins
**Today** (who is in, who is late / absent / on leave, any day), **Requests** (approve / deny / edit / unlink),
**Teachers** (rename), **Schedule** (view faculty weeks and **edit shift times in Philippine time**; the desktop
app picks the change up on its next sync and rewrites `Employee Form.xls`), **Notices** (post, pin, delete).

## Notifications (Android, no Google services)
| Who | Gets notified when |
|---|---|
| Teacher | **~20 min before the first log-in** of the day ("Time to log in"); marked late; no log-out recorded after the duty; a new notice; request approved / denied; unlink decided |
| Admin | a new link request; a teacher asks to unlink |

Every minute while the app is open, roughly every 15 minutes in the background (Android's minimum). Each
reminder fires once a day. Not instant; battery saver can delay it.

## Setup
1. Supabase SQL: run `supabase/setup_all.sql` once (see the root README).
2. Authentication → enable *Email* and *Google*; add the redirect URL `io.supabase.cnhs://login-callback/`.
3. `flutter create --platforms=android,ios,web .` then `flutter pub get` (CI does this and patches the Android
   manifest / Gradle for you).
4. Run: `flutter run --dart-define=SUPABASE_URL=https://YOUR.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY`
   (anon key only, never the service-role key).
5. Make yourself admin after signing up once:
   `insert into app_admins (user_id) select id from auth.users where email = 'you@school.edu';`

On Xiaomi / Oppo / Vivo / Huawei / Samsung set the app's battery mode to **Unrestricted** or background checks may be killed.

## Notes
* `lib/schedule_calc.dart` is shared byte-for-byte with the desktop app (`lib/core/schedule_calc.dart`); CI fails if they differ.
* `flutter test` runs the day-status logic (on time / late / absent / leave / today) and the Philippine-time helpers.
