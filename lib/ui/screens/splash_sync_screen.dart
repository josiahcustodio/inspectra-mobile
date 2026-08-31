import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../data/services/offline_service.dart';
import 'main_navigation_screen.dart';

class SplashSyncScreen extends StatefulWidget {
  const SplashSyncScreen({super.key});

  @override
  State<SplashSyncScreen> createState() => _SplashSyncScreenState();
}

class _SplashSyncScreenState extends State<SplashSyncScreen> {
  String _statusMessage = 'Initializing Offline Database...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _statusMessage = 'Syncing templates and establishments...';
      });
      // Basic sync call to fetch data and store it in Hive
      await OfflineService.syncData();

      setState(() {
        _statusMessage = 'Sync Complete! Ready for inspection.';
      });

      // Small delay for UX, so the user knows sync was successful
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      // Navigate to the primary workflow
      context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage =
              'Error during sync: $e\nProceeding with cached data.';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).colorScheme.primary, // Sage Green primary
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.health_and_safety,
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                'City Health Office\nInspector Portal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
