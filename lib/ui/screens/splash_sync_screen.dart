import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/offline_service.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

class SplashSyncScreen extends StatefulWidget {
  const SplashSyncScreen({super.key});

  @override
  State<SplashSyncScreen> createState() => _SplashSyncScreenState();
}

class _SplashSyncScreenState extends State<SplashSyncScreen> {
  String _statusMessage = 'Initializing Offline Database...';

  /// Owners see no inspector copy on this screen, and no sync status, because
  /// neither applies to them.
  bool _isOwner = false;

  /// The role could not be read and the splash is parked: show a way out.
  bool _roleFailed = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // [REF: STARTUP_SYNC]
  Future<void> _initializeApp() async {
    // [REF: ROLE_ROUTE_BRANCH]
    // The role is resolved HERE, before anything else happens, because the
    // whole shape of startup depends on it — and because the router pins an
    // unresolved role to this screen, making it the one place that can settle
    // the question without flashing a destination first.
    final auth = context.read<AuthProvider>();
    final role = await auth.ensureRole();
    if (!mounted) return;

    if (role == 'owner') {
      setState(() {
        _isOwner = true;
        _statusMessage = 'Loading your inspection records...';
      });
      // No syncData(): the establishment and checklist caches it fills are
      // inspector tooling an owner has no access to and no use for.
      context.go('/my/inspections');
      return;
    }

    // Not routed here — the router's own guard sends a pending account to its
    // screen as soon as the role resolves, and it has already run by now.
    // Falling through to a sync for a role that can read nothing would just
    // log three permission-shaped empty results.
    if (role == 'pending') return;

    // [REF: ROLE_UNKNOWN_DEADLOCK]
    // Still unknown after ensureRole() AND after its cached fallback: this
    // device has never successfully read a role for this account and cannot
    // reach the network now. Stop here rather than syncing and calling
    // context.go('/home') — the router pins an unknown role back to /sync, so
    // that call rebuilt this screen and ran initState again, forever.
    //
    // The message is the exit: the account has to be online once, and saying
    // so beats a spinner that never resolves.
    if (role == null) {
      setState(() {
        _roleFailed = true;
        _statusMessage =
            'Could not confirm your account. Connect to the internet once, '
            'then reopen the app.';
      });
      return;
    }

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
      // brandStrong rather than the brand itself: every word on this screen is
      // white on this ground, and the status line is 14pt. White on `brand` is
      // 3.77:1 and fails AA at that size; on brandStrong it is 5.48:1.
      backgroundColor: AppColors.brandStrong,
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
              Text(
                _isOwner
                    ? 'City Health Office\nInspection Records'
                    : 'City Health Office\nInspector Portal',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 48),
              if (!_roleFailed)
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
              if (_roleFailed) ...[
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.brandStrong,
                  ),
                  onPressed: () {
                    setState(() {
                      _roleFailed = false;
                      _statusMessage = 'Checking your account...';
                    });
                    _initializeApp();
                  },
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => context.read<AuthProvider>().signOut(),
                  child: const Text('Sign out', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
