/// Supabase project configuration.
///
/// Compiled in rather than read from a .env, same stance firebase_options.dart
/// took: these values are public by design (the publishable key is shipped in
/// every client), and row-level security — not secrecy — is what protects the
/// data. See migration/sql/02_rls.sql in the Inspectra root.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://fwtgdgeiffnvqyrobixc.supabase.co';
  static const String publishableKey =
      'sb_publishable_ihs90H1D6-8lxrrFrTC-NQ_-vwZcktI';

  /// The WEB OAuth client of Google Cloud project cityhealth-492614 — the
  /// client whose id Supabase's Google provider is configured to accept and
  /// whose registered redirect URI is this project's /auth/v1/callback.
  /// google_sign_in needs it as serverClientId so the minted idToken carries
  /// an audience Supabase will trust. (google-services.json is gone; this is
  /// the only Google client id the app references.)
  ///
  /// Created fresh 2026-10-07, replacing the client whose secret had leaked
  /// into the repo tree (the old 313568455152-9djq... client should be
  /// deleted in the Google console).
  static const String googleServerClientId =
      '313568455152-qs5cf1klheesoo2u75k7nruqvtbtsemi.apps.googleusercontent.com';
}
