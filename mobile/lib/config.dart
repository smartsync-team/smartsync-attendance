/// Build-time configuration.
///
/// Values come from `--dart-define-from-file=env.json` (see env.example.json),
/// so the same code builds for test and production Supabase projects.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  /// The project's publishable key (sb_publishable_…) or legacy anon key.
  /// Safe to ship in the APK — row level security protects the data.
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  /// Only allow sign-ups from this email domain, e.g. "eng.ruh.ac.lk".
  /// Empty = any email.
  static const allowedEmailDomain = String.fromEnvironment('ALLOWED_EMAIL_DOMAIN');

  /// Students below this attendance percentage are flagged.
  static const eligibilityThreshold = 80.0;

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
