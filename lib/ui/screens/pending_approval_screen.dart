import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

// [REF: PENDING_APPROVAL]
//
// Where a brand-new account waits.
//
// This screen exists because of the provisioning fix, not alongside it. New
// accounts used to be stamped 'officer' by handle_new_user() and worked
// immediately — which is precisely the hole 05_app_role_pending.sql closes.
// A new account is now 'pending', and every policy in 02_rls.sql denies that
// role, so the session is real but can reach no data whatsoever.
//
// Without this screen the fix would land someone on a home screen of empty
// lists with nothing to explain it: an inspector who would reasonably
// conclude the app is broken, and file it as a bug rather than ask to be
// activated. Saying so plainly is the difference between a security fix and a
// support problem.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: const BoxDecoration(
                    color: AppColors.brandSurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.how_to_reg_rounded,
                    size: 40,
                    color: AppColors.brandStrong,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Waiting for activation',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: '.SF Pro Display',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: AppColors.textDisplay,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your account was created, but an administrator at the City '
                  'Health Office still has to activate it before you can '
                  'start inspecting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 14,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppTheme.cardRadius,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Signed in as',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        auth.user?.email ?? 'Unknown account',
                        style: const TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDisplay,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Give this address to your administrator — it is what '
                        'they activate.',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 12,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Manual rather than polled. The auth listener resolves the
                // role once per session, and an approval happens on someone
                // else's screen minutes or hours later — a background poll
                // would spend the battery of every waiting account to save one
                // tap.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: auth.isLoading
                        ? null
                        : () async {
                            await context.read<AuthProvider>().refreshRole();
                            if (!context.mounted) return;
                            // Still pending: the router would not have moved
                            // us, so say something rather than appear inert.
                            if (context.read<AuthProvider>().isPendingApproval) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Not activated yet. Try again in a '
                                      'little while.'),
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandStrong,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: AppTheme.buttonRadius),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Check again',
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.read<AuthProvider>().signOut(),
                  child: const Text(
                    'Sign out',
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
