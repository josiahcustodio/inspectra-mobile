import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'data/services/offline_service.dart';
import 'providers/rating_provider.dart';
import 'providers/pending_inspections_provider.dart';
import 'providers/inspection_history_provider.dart';
import 'providers/auth_provider.dart';
import 'core/router/app_router.dart';
// [REF: APP_BOOTSTRAP]
void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Scaffold(
        body: SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'UI CRASH:\n${details.exception}\n\n${details.stack}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        ),
      );
    };

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize offline storage
    await Hive.initFlutter();
    await OfflineService.init();

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
  } catch (e, stack) {
    runApp(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'STARTUP CRASH:\n$e\n\n$stack',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

class ClowtecInspectorApp extends StatelessWidget {
  const ClowtecInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final router = createAppRouter(authProvider);

    return MaterialApp.router(
      title: 'Inspectra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
