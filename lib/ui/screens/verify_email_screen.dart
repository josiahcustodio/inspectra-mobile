import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

/// Blocks access until the signed-in user verifies their email — a
/// prerequisite for TOTP MFA enrollment. Reached only when
/// [AuthProvider.needsEmailVerification] is true; the router bounces back
/// if the user tries to navigate away before verifying.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _pollTimer;
  bool _resent = false;

  @override
  void initState() {
    super.initState();
    // Poll every few seconds so the app notices as soon as the user
    // clicks the link, without requiring a manual "I've verified" tap.
    // [REF: EMAIL_VERIFY_POLLING]
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      Provider.of<AuthProvider>(context, listen: false).refreshEmailVerified();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final email = authProvider.user?.email ?? 'your email';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
                color: const Color(0xFF0D9488).withValues(alpha: 0.15),
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
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
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
                  const Icon(Icons.mark_email_unread_outlined,
                      size: 56, color: Color(0xFF0D9488)),
                  const SizedBox(height: 16),
                  const Text(
                    'Verify Your Email',
                    style: TextStyle(
                      fontFamily: '.SF Pro Display',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: Color(0xFF0D9488),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification link to $email. Open it, then come back here — '
                    'this checks automatically every few seconds. Email verification is required '
                    'before setting up two-factor authentication.',
                    style: const TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  const Center(child: CircularProgressIndicator(color: Color(0xFF0A2540))),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: authProvider.isLoading
                        ? null
                        : () async {
                            final success = await authProvider.resendVerificationEmail();
                            if (context.mounted) {
                              setState(() => _resent = success);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(success
                                      ? 'Verification email resent.'
                                      : authProvider.errorMessage ?? 'Could not resend email.'),
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(_resent ? 'Email Sent' : 'Resend Verification Email'),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: authProvider.isLoading ? null : () => authProvider.signOut(),
                      child: const Text(
                        'Not you? Sign out',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          color: Color(0xFF64748B),
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
