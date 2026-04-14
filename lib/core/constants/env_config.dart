import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  static String get url => dotenv.env['SUPABASE_URL'] ?? '';
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  // Google Auth Client IDs
  static String get webClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  static String get iosClientId => dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '';
}
