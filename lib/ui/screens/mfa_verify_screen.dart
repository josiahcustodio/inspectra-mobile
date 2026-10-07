import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';

/// Sign-in-time TOTP challenge. Reached when a session exists at AAL1 but
/// the account has a verified TOTP factor ([AuthProvider.mfaChallengePending])
/// — the code entered here upgrades that same session to AAL2. Until it
/// does, the restrictive RLS policies refuse every table and storage read,
/// so the router pins the user to this screen; there is no data to show
/// anywhere else anyway.
class MfaVerifyScreen extends StatefulWidget {
  const MfaVerifyScreen({super.key});

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _codeController = TextEditingController();
  String? _codeError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // [REF: MFA_VERIFY_SCREEN]
  Future<void> _verify(AuthProvider authProvider) async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _codeError = 'Enter the 6-digit code');
      return;
    }
    setState(() => _codeError = null);

    final success = await authProvider.completeMfaSignIn(code);
    if (!success && mounted) {
      setState(() {
        _codeError = authProvider.errorMessage ?? 'Incorrect code. Please try again.';
      });
    }
    // On success, the auth-state listener + router redirect take over.
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (!authProvider.mfaChallengePending) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Session expired',
                    style: TextStyle(
                      fontFamily: '.SF Pro Display',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDisplay,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please sign in again to continue.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandStrong,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Back to Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brand.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandStrong.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  const Icon(Icons.shield_outlined, size: 48, color: AppColors.brand),
                  const SizedBox(height: 16),
                  const Text(
                    'Two-Factor Authentication',
                    style: TextStyle(
                      fontFamily: '.SF Pro Display',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: AppColors.brand,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter the 6-digit code from your authenticator app.',
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 8, fontFamily: '.SF Pro Text'),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.brandStrong, width: 1.5),
                      ),
                      errorText: _codeError,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: authProvider.isLoading ? null : () => _verify(authProvider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandStrong,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: authProvider.isLoading
                        ? const SizedBox(
                            height: 4,
                            width: 100,
                            child: LinearProgressIndicator(
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          )
                        : const Text(
                            'Verify',
                            style: TextStyle(
                              fontFamily: '.SF Pro Text',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        authProvider.cancelMfaChallenge();
                        context.go('/login');
                      },
                      child: const Text(
                        'Cancel / use a different account',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
