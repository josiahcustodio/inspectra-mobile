import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/password_rules.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

// [REF: OWNER_SET_PASSWORD]
/// Where the router holds an owner after their first, code-only sign-in until
/// the account has a password. The rules are listed and ticked off as they
/// type; PasswordRules is the same check the Save button runs.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final blocker = PasswordRules.blocker(_password.text) ??
        (_password.text != _confirm.text ? 'Passwords do not match.' : null);
    if (blocker != null) {
      setState(() => _error = blocker);
      return;
    }
    setState(() => _error = null);
    final auth = context.read<AuthProvider>();
    // On success the router sees password_set and leaves this screen itself.
    if (!await auth.setOwnerPassword(_password.text) && mounted) {
      setState(() => _error = auth.errorMessage ?? 'Could not save the password.');
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final level = PasswordRules.level(_password.text);
    final total = PasswordRules.rules.length;
    final levelColor =
        level == total ? AppColors.brand : (level >= 3 ? Colors.orange : Colors.redAccent);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDisplay,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Set your password'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: auth.isLoading ? null : () => auth.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your email is verified. Choose a password so next time you '
                'can sign in with your email and password.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _password,
                obscureText: _obscure,
                enabled: !auth.isLoading,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('New password'),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: level / total,
                color: levelColor,
                backgroundColor: AppColors.border,
                minHeight: 6,
                semanticsLabel: 'Password strength',
                semanticsValue: '$level of $total rules met',
              ),
              const SizedBox(height: 12),
              for (final (label, pattern) in PasswordRules.rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        pattern.hasMatch(_password.text)
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: pattern.hasMatch(_password.text)
                            ? AppColors.brand
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(label, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                enabled: !auth.isLoading,
                decoration: _decoration('Confirm password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: auth.isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandStrong,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(auth.isLoading ? 'Saving…' : 'Save password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
