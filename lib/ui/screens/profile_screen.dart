import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/services/auth_service.dart';
import '../../data/services/mfa_service.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';

// [REF: PROFILE_SCREEN]
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _showMfaSheet(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Two-Factor Authentication',
          style: TextStyle(
              fontFamily: '.SF Pro Display',
              fontWeight: FontWeight.bold,
              color: AppColors.textDisplay),
        ),
        content: const Text(
          'Two-factor authentication is required and currently enabled on this account.\n\n'
          'If you\'re switching to a new phone or lost access to your authenticator app, '
          'you can reset it here — you\'ll need to set up a new one immediately after.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Close',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              ctx.pop();
              _confirmReset(context, authProvider);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
            child: const Text('Reset Authenticator',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Reset Authenticator?',
            style: TextStyle(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.bold,
                color: AppColors.textDisplay)),
        content: const Text(
          'This removes your current authenticator and immediately requires setting up a new one. Continue?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              ctx.pop();
              if (authProvider.user == null) return;
              try {
                await MfaService.resetAuthenticator();
                await authProvider.refreshMfaStatus();
                // Router redirect sends the user to /mfa-enroll automatically.
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
            child: const Text('Reset',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ─── My Account Dialog ──────────────────────────────────────────────────────
  Future<void> _editFullName(BuildContext context) async {
    final controller =
        TextEditingController(text: AuthService.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Full name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Juan M. Dela Cruz'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      await AuthService.updateDisplayName(name);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Name updated.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update name. Try again.')));
      }
    }
  }

  void _showMyAccount(BuildContext context) {
    final user = AuthService.currentUser;
    final name = AuthService.displayName ?? 'Inspector';
    final email = user?.email ?? 'No email';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.brand.withValues(alpha: 0.15),
              child: const Icon(Icons.person_rounded,
                  size: 40, color: AppColors.brand),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDisplay,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              email,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _accountRow(Icons.badge_outlined, 'Department', 'City Health Office'),
            const SizedBox(height: 8),
            _accountRow(Icons.verified_user_outlined, 'Role', _roleLabel(context)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _accountRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Expanded(
          child: Text(value,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  String _roleLabel(BuildContext context) {
    switch (context.read<AuthProvider>().role) {
      case 'admin':
        return 'Administrator';
      case 'department_head':
        return 'Department Head';
      case 'owner':
        return 'Establishment Owner';
      default:
        return 'Field Inspector';
    }
  }

  // ─── Help & Support Dialog ───────────────────────────────────────────────────
  void _showHelpSupport(BuildContext context) {
    final faqs = [
      {
        'q': 'How do I start a new inspection?',
        'a':
            'Tap "New Inspection" on the Home screen, then search for the establishment by name or ID.',
      },
      {
        'q': 'What happens when I submit offline?',
        'a':
            'The inspection is saved on your device. When you are back online, tap Sync Now or Submit All on the Pending card of the Home screen to send it.',
      },
      {
        'q': 'How is the rating score calculated?',
        'a':
            'The score starts at 100. Each "Fail" answer deducts demerit points based on the weight of that checklist item. The final percentage determines the rating: 90–100 Excellent, 70–89 Very Satisfactory, 0–69 Satisfactory.',
      },
      // Answered "Yes ... tap the pencil icon" until 2026-10-04,
      // describing a screen this app has not had since Chunk 1. There is
      // no edit route at all - see the comment on the establishment routes
      // in app_router.dart - and tapping an establishment starts an
      // inspection. The web admin owns this data, so the only useful
      // answer is where to go instead.
      {
        'q': 'Can I edit an establishment\'s details?',
        'a':
            'No - establishment records are managed on the web admin dashboard, not in this app. Tapping an establishment here starts an inspection. If a name, owner or address is wrong, ask the City Health Office admin to correct it on the dashboard; the correction reaches your phone on the next sync.',
      },
      {
        'q': 'Who do I contact for technical issues?',
        'a':
            'Contact the City Health Office IT Department or your system administrator for any technical concerns.',
      },
    ];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.help_outline_rounded,
                      color: AppColors.brand, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Help & Support',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDisplay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: SingleChildScrollView(
                  child: Column(
                    children: faqs
                        .map((faq) => _FaqTile(
                              question: faq['q']!,
                              answer: faq['a']!,
                            ))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final displayName =
        AuthService.displayName ?? user?.email ?? 'Inspector';
    final subtitle = user?.email ?? 'City Health Office';
    final photoUrl = AuthService.photoUrl;

    return Scaffold(
      // A bottom tab again, so no back arrow appears: the branch has no history.
      appBar: AppBar(title: const Text('Profile'), backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),
              CircleAvatar(
                radius: 48,
                backgroundColor: primary.withValues(alpha: 0.15),
                backgroundImage:
                    photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
                    ? Icon(Icons.person_rounded, size: 52, color: primary)
                    : null,
              ),
              const SizedBox(height: 14),
              Text(
                displayName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
              const SizedBox(height: 32),
              _ProfileTile(
                icon: Icons.badge_outlined,
                label: 'My Account',
                onTap: () => _showMyAccount(context),
              ),
              _ProfileTile(
                icon: Icons.drive_file_rename_outline_rounded,
                label: 'Full name',
                subtitle: 'Printed on inspections and Sanitary Orders',
                onTap: () => _editFullName(context),
              ),
              _ProfileTile(
                icon: Icons.security_rounded,
                label: 'Two-Factor Authentication',
                subtitle: authProvider.hasTotpEnrolled == true ? 'Enabled' : 'Setting up…',
                onTap: () => _showMfaSheet(context, authProvider),
              ),
              _ProfileTile(
                icon: Icons.help_outline_rounded,
                label: 'Help & Support',
                onTap: () => _showHelpSupport(context),
              ),
              _ProfileTile(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                onTap: () async {
                  // Confirm before signing out
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Sign Out'),
                      content:
                          const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await authProvider.signOut();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  }
                },
                isDestructive: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── FAQ Tile Widget ──────────────────────────────────────────────────────────

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.question,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textDisplay,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              widget.answer,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

// ─── Profile Tile ─────────────────────────────────────────────────────────────

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ProfileTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red.shade400 : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: color)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
