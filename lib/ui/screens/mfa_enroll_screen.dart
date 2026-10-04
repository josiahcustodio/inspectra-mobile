import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/services/mfa_service.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';

/// Mandatory TOTP enrollment screen. Reached only when the signed-in user
/// has no TOTP factor enrolled yet — the router forces this and bounces
/// back if the user tries to navigate away before finishing.
class MfaEnrollScreen extends StatefulWidget {
  const MfaEnrollScreen({super.key});

  @override
  State<MfaEnrollScreen> createState() => _MfaEnrollScreenState();
}

class _MfaEnrollScreenState extends State<MfaEnrollScreen> {
  final _codeController = TextEditingController();

  bool _loadingSecret = true;
  bool _submitting = false;
  bool _needsRecentLogin = false;
  String? _loadError;
  String? _codeError;
  bool _showManualKey = false;
  TotpSecret? _secret;
  String? _qrUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startEnrollment());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // [REF: MFA_ENROLL_SCREEN]
  Future<void> _startEnrollment() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) return;

    setState(() {
      _loadingSecret = true;
      _loadError = null;
      _needsRecentLogin = false;
    });

    try {
      final secret = await MfaService.startEnrollment(user);
      final qrUrl = await MfaService.buildQrUrl(
        secret,
        accountName: user.email ?? user.uid,
      );
      if (!mounted) return;
      setState(() {
        _secret = secret;
        _qrUrl = qrUrl;
        _loadingSecret = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _loadError = message;
        _needsRecentLogin = message.contains('sign out and sign in again');
        _loadingSecret = false;
      });
    }
  }

  // [REF: MFA_ENROLL_VERIFY]
  Future<void> _verify() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final secret = _secret;
    final code = _codeController.text.trim();

    if (user == null || secret == null) return;
    if (code.length != 6) {
      setState(() => _codeError = 'Enter the 6-digit code');
      return;
    }

    setState(() {
      _submitting = true;
      _codeError = null;
    });

    try {
      await MfaService.completeEnrollment(
        user: user,
        secret: secret,
        code: code,
        displayName: 'Authenticator App',
      );
      await authProvider.refreshMfaStatus();
      // Router redirect takes over from here.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _codeError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

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
                  const SizedBox(height: 24),
                  const Text(
                    'Set Up Two-Factor Authentication',
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
                    'This is required for every Inspectra account. Scan the QR code below with Google Authenticator (or a similar app), then enter the code it shows.',
                    style: TextStyle(
                      fontFamily: '.SF Pro Text',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  _buildBody(),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: authProvider.isLoading
                          ? null
                          : () => authProvider.signOut(),
                      child: const Text(
                        'Not you? Sign out',
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

  Widget _buildBody() {
    if (_loadingSecret) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(color: AppColors.brandStrong),
        ),
      );
    }

    if (_loadError != null) {
      return Column(
        children: [
          Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _needsRecentLogin
                ? () => Provider.of<AuthProvider>(context, listen: false).signOut()
                : _startEnrollment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandStrong,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(_needsRecentLogin ? 'Sign Out and Try Again' : 'Try Again'),
          ),
        ],
      );
    }

    final qrUrl = _qrUrl;
    final secret = _secret;
    if (qrUrl == null || secret == null) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: qrUrl,
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _showManualKey = !_showManualKey),
          child: Text(
            _showManualKey ? 'Hide manual code' : "Can't scan? Enter code manually",
            style: const TextStyle(
              fontFamily: '.SF Pro Text',
              color: AppColors.brandStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_showManualKey)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(
              secret.secretKey,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                letterSpacing: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '6-Digit Code',
            style: TextStyle(
              fontFamily: '.SF Pro Text',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
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
          onPressed: _submitting ? null : _verify,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandStrong,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: _submitting
              ? const SizedBox(
                  height: 4,
                  width: 100,
                  child: LinearProgressIndicator(
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                )
              : const Text(
                  'Verify & Enable',
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }
}
