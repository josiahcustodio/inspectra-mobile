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
}
