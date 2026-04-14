import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final file = File('.env');
  final lines = await file.readAsLines();
  String? url;
  String? anonKey;
  for (var line in lines) {
    if (line.trim().startsWith('SUPABASE_URL=')) {
      url = line.split('=')[1].trim();
    } else if (line.trim().startsWith('SUPABASE_ANON_KEY=')) {
      anonKey = line.split('=')[1].trim();
    }
  }

  if (url == null || anonKey == null) {
    print('Missing URL or ANON_KEY');
    return;
  }

  final client = SupabaseClient(url, anonKey);

  try {
    print('Fetching categories...');
    final categories = await client.from('categories').select();
    print('Categories: ${categories.length}');
    print(categories);

    print('Fetching checklist_templates...');
    final templates = await client.from('checklist_templates').select();
    print('Templates: ${templates.length}');
    print(templates);

  } catch (e) {
    print('Error: $e');
  }
}
