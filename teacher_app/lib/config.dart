// Supply these at build/run time so no keys live in source control:
//   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
// Use the *anon* (public) key only. Never put the service-role key in this app.
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// Must match the redirect URL added in Supabase > Authentication > URL Configuration
// and the intent filter / URL scheme in the Android / iOS project (see README).
const String kOAuthRedirect = 'io.supabase.cnhs://login-callback/';
