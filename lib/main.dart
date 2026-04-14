import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/env_config.dart';
import 'core/theme/app_theme.dart';
import 'data/services/offline_service.dart';
import 'providers/rating_provider.dart';
import 'providers/pending_inspections_provider.dart';
import 'providers/inspection_history_provider.dart';
import 'providers/auth_provider.dart';
import 'ui/screens/auth_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialize offline storage
  await Hive.initFlutter();
  await OfflineService.init();

  // Initialize Supabase if keys are provided
  if (SupabaseConfig.url.isNotEmpty &&
      SupabaseConfig.anonKey.isNotEmpty &&
      !SupabaseConfig.url.contains('YOUR_SUPABASE')) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RatingProvider()),
        ChangeNotifierProvider(create: (_) => PendingInspectionsProvider()),
        ChangeNotifierProvider(create: (_) => InspectionHistoryProvider()),
      ],
      child: const ClowtecInspectorApp(),
    ),
  );
}

class ClowtecInspectorApp extends StatelessWidget {
  const ClowtecInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clowtec Inspector',
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
    );
  }
}
