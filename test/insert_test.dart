import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Test Supabase Insert', () async {
    const supabaseUrl = 'https://fwtgdgeiffnvqyrobixc.supabase.co';
    const supabaseKey = 'sb_publishable_ihs90H1D6-8lxrrFrTC-NQ_-vwZcktI';

    final client = SupabaseClient(supabaseUrl, supabaseKey);

    final payload = {
      // 'id': '1234567890',  // uuid auto-handled by supabase
      'category_id': 1, // Valid ID based on your screenshot
      'business_name': 'Test Establishment RLS',
      'address': 'Test Address 123',
      'owner_name': 'Juan Dela Cruz',
      'personnel_count': 5,
      'personnel_with_hc': 5,
      'sanitary_permit_no': 'SP-12345',
      'control_no': 'CN-12345',
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      final response = await client.from('establishments').insert(payload);
      print('Insert Success: $response');
    } catch (e) {
      print('Insert Error: $e');
      fail('Insert failed with error: $e');
    }
  });
}
