import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

import '../../data/services/mfa_service.dart';
import '../../providers/auth_provider.dart';

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
              color: Color(0xFF0F172A)),
        ),
        content: const Text(
          'Two-factor authentication is required and currently enabled on this account.\n\n'
          'If you\'re switching to a new phone or lost access to your authenticator app, '
          'you can reset it here — you\'ll need to set up a new one immediately after.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
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
                color: Color(0xFF0F172A))),
        content: const Text(
          'This removes your current authenticator and immediately requires setting up a new one. Continue?',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              ctx.pop();
              final user = authProvider.user;
              if (user == null) return;
              try {
                await MfaService.resetAuthenticator(user);
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
  void _showMyAccount(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Inspector';
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
              backgroundColor: const Color(0xFF10B981).withOpacity(0.15),
              child: const Icon(Icons.person_rounded,
                  size: 40, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
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
            _accountRow(Icons.verified_user_outlined, 'Role', 'Field Inspector'),
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

  // ─── Settings Dialog ─────────────────────────────────────────────────────────
  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _SettingsDialog(),
    );
  }

  // ─── Help & Support Dialog ───────────────────────────────────────────────────
  void _showHelpSupport(BuildContext context) {
    final faqs = [
      {
        'q': 'How do I start a new inspection?',
        'a':
            'Tap the green "New Inspection" button on the Home screen, then search for the establishment by name or scan its QR code.',
      },
      {
        'q': 'What happens when I submit offline?',
        'a':
            'The inspection is saved locally on your device. It will automatically sync to the server the next time you have an internet connection. You can also manually sync from the Pending card on the Home screen.',
      },
      {
        'q': 'How is the rating score calculated?',
        'a':
            'The score starts at 100. Each "Fail" answer deducts demerit points based on the weight of that checklist item. The final percentage determines the rating: ≥90 Excellent, ≥70 Very Satisfactory, ≥50 Satisfactory, <50 Action Required.',
      },
      {
        'q': 'Can I edit an establishment\'s details?',
        'a':
            'Yes. Go to the Establishments tab, tap the establishment, then tap the pencil icon in the top-right corner to edit its details.',
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
                      color: Color(0xFF10B981), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Help & Support',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
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
    final displayName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : user?.email ?? 'Inspector';
    final subtitle = user?.email ?? 'City Health Office';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),
              CircleAvatar(
                radius: 48,
                backgroundColor: primary.withValues(alpha: 0.15),
                backgroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: user?.photoURL == null
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
                icon: Icons.security_rounded,
                label: 'Two-Factor Authentication',
                subtitle: authProvider.hasTotpEnrolled == true ? 'Enabled' : 'Setting up…',
                onTap: () => _showMfaSheet(context, authProvider),
              ),
              _ProfileTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => _showSettings(context),
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

// ─── Settings Dialog Widget ───────────────────────────────────────────────────

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool _notificationsEnabled = true;
  bool _soundEnabled = false;
  bool _autoSync = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.settings_outlined, color: Color(0xFF10B981), size: 22),
          SizedBox(width: 10),
          Text('Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SettingsTile(
            label: 'Push Notifications',
            subtitle: 'Receive sync and update alerts',
            value: _notificationsEnabled,
            onChanged: (val) => setState(() => _notificationsEnabled = val),
          ),
          const Divider(height: 1),
          _SettingsTile(
            label: 'Sound',
            subtitle: 'Play sounds on submission',
            value: _soundEnabled,
            onChanged: (val) => setState(() => _soundEnabled = val),
          ),
          const Divider(height: 1),
          _SettingsTile(
            label: 'Auto-Sync',
            subtitle: 'Sync pending items automatically',
            value: _autoSync,
            onChanged: (val) => setState(() => _autoSync = val),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14,
                        color: Color(0xFF0F172A))),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF10B981),
          ),
        ],
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
                      color: Color(0xFF0F172A),
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
