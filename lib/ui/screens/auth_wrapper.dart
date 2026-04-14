import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'login_screen.dart';
import 'splash_sync_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to changes in authentication state
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isAuthenticated) {
      // If authenticated, navigate to SplashSyncScreen to perform data sync
      // which will then naturally navigate to MainNavigationScreen.
      return const SplashSyncScreen();
    } else {
      // Otherwise, show LoginScreen
      return const LoginScreen();
    }
  }
}
