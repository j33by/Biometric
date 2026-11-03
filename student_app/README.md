# CNHS Student App

Flutter app (Android / iOS / web) for students and admins. It talks straight to the
**same Supabase project** as the Biometric desktop app, protected by row level security.

## How it works
1. Student signs up (Google or email + password) and searches their name.
2. They pick the biometric record and send a request. (Google/e-mail sign-in only proves who they
   are; **nothing is visible until an admin approves**.)
3. Admin opens **Requests** and can **Approve**, **Deny** (with a reason), or **Edit**:
   - the name shown on the account,
   - the student record's own name (this renames the biometric record),
   - which student record the account is bound to.
4. Once approved the student gets: **Home** (today's punches + latest notices), **Attendance**
   (month calendar, In/Out per day), **Logs** (every punch, last 60 days), **Notices**
   (everyone or per section) and **Profile**.

Admin tabs: **Requests** (Pending / Approved / Denied / **Unlink**), **Students** (rename), **Notices** (post / pin / delete), **Account**.

### Request unlink
An approved student can open **Profile > Request unlink** and give a reason (wrong record, new account...).
The admin sees it under **Requests > Unlink** and either **Approves** (the link is deleted, the student
can search and bind again) or **Keeps linked** with a note shown to the student. The student can cancel
their request while it is waiting.

### Notifications (Android only, no Google services)
The app checks Supabase itself and shows a normal phone notification. No Firebase, no server code.

| Who | Gets notified when |
|---|---|
| Approved students | a new notice is posted (only for their section if the notice targets one) |
| The student | their request is approved or denied; their unlink request is approved or declined |
| Admins | a new link request arrives; a student asks to unlink |

How fast: every minute while the app is open, and about every 15 minutes in the background
(Android's minimum for background work; phones in battery saver / Doze may delay it more). It is not instant.
The first check after signing in only records the current state, so old notices do not flood the phone.
iOS and web get no notifications.

## Setup
1. **Supabase SQL**: SQL Editor > run `supabase/student_app.sql` (after the existing `schema.sql`).
2. **Auth providers**: Supabase > Authentication > Providers: enable *Email* and *Google*
   (create an OAuth client in Google Cloud Console; paste the client id/secret; add the Supabase
   callback URL it shows to the Google client's authorised redirect URIs).
3. **Redirect URL**: Authentication > URL Configuration > add `io.supabase.cnhs://login-callback/`
   (and your web URL if you deploy to web).
4. **Create the project files**: in this folder run `flutter create --platforms=android,ios,web .`
   (it only adds the missing platform folders), then `flutter pub get`.
5. **Deep link** (needed for Google sign-in and email links on phones):
   - Android `android/app/src/main/AndroidManifest.xml`, inside `<activity ...>`:
     ```xml
     <intent-filter>
       <action android:name="android.intent.action.VIEW"/>
       <category android:name="android.intent.category.DEFAULT"/>
       <category android:name="android.intent.category.BROWSABLE"/>
       <data android:scheme="io.supabase.cnhs" android:host="login-callback"/>
     </intent-filter>
     ```
   - iOS `ios/Runner/Info.plist`: add a `CFBundleURLTypes` entry with scheme `io.supabase.cnhs`.
6. **Run**:
   `flutter run --dart-define=SUPABASE_URL=https://YOUR.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY`
   Use the **anon** key only, never the service-role key.
7. **Make yourself admin**: sign up in the app once, then in the SQL Editor:
   `insert into app_admins (user_id) select id from auth.users where email = 'you@school.edu';`

## Enabling unlink + notifications (run after the steps above)
1. **SQL**: run `supabase/unlink_request.sql` in the SQL Editor.
2. **Android project** (after `flutter create`, then `flutter pub get`):
   - `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
     `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`
   - `android/app/build.gradle.kts` (needed by flutter_local_notifications):
     ```kotlin
     android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
     dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
     ```
3. On the phone: allow notifications when asked. On Xiaomi / Oppo / Vivo / Huawei / Samsung also set the app's
   battery mode to **Unrestricted** (and allow auto-start), otherwise the phone may kill background checks.

## Notes
- Renaming a student here bumps `updated_at`, so the desktop app picks it up on its next cloud sync
  and writes it into `Employee Form.xls` for the device.
- Attendance shows first punch = In, last punch = Out, matching the desktop app. Late/early
  minutes are not shown yet.
- Email sign-up needs "Confirm email" handling: with it on, students confirm by email before signing in.
