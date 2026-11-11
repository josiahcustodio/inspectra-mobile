import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../data/services/auth_service.dart';
import '../../core/theme/app_colors.dart';

// [REF: LOGIN_SCREEN]
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: Stack(
        children: [
          // Background Dynamic Shapes
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
          // Global Background Blur (Glassmorphism)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // Clean, modern 'Inspectra' logo at the top
              const Text(
                'Inspectra',
                style: TextStyle(
                  fontFamily: '.SF Pro Display',
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: AppColors.brand,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // Email Input Field
              const Text(
                'Email',
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: const TextStyle(fontFamily: '.SF Pro Text'),
                decoration: InputDecoration(
                  hintText: 'name@example.com',
                  hintStyle: const TextStyle(color: Colors.black38, fontFamily: '.SF Pro Text'),
                  contentPadding: const EdgeInsets.all(16),
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
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Email is required';
                  final emailRegex = RegExp(r'^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$');
                  if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Password Input Field
              const Text(
                'Password',
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(fontFamily: '.SF Pro Text'),
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  hintStyle: const TextStyle(color: Colors.black38, fontFamily: '.SF Pro Text'),
                  contentPadding: const EdgeInsets.all(16),
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
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.black54,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Password is required';
                  if (value.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _showForgotPasswordDialog(context),
                child: const Text(
                  'Forgot Password?',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.brandStrong,
                    fontFamily: '.SF Pro Text',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: authProvider.isLoading
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;

                      final email = _emailController.text.trim();
                      final password = _passwordController.text;

                      final success = await authProvider.signInWithEmailPassword(email, password);
                      if (!success && authProvider.errorMessage != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(authProvider.errorMessage!)),
                        );
                      }
                    },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandStrong,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                        'Sign In',
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              Center(
                child: InkWell(
                  onTap: () => _showSignUpDialog(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Don\'t have an account? Sign Up',
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 14,
                        color: AppColors.brandStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // [REF: OWNER_SIGNIN_ENTRY]
              // Below a divider rather than beside the inspector fields: these
              // are two different audiences, and an establishment owner has no
              // password to put in the form above — their sign-in is a mailed
              // code and nothing else.
              Row(
                children: [
                  Expanded(child: Container(height: 1, color: AppColors.border)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: Container(height: 1, color: AppColors.border)),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: InkWell(
                  onTap: () => _showOwnerSignInDialog(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Text(
                          'I own or manage an establishment',
                          style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 14,
                            color: AppColors.brandStrong,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'View your inspection results',
                          style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
    ],
   ),
  );
  }

  InputDecoration _dialogInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: '.SF Pro Text'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  // [REF: FORGOT_PASSWORD_DIALOG]
  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController(text: _emailController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Reset Password', style: TextStyle(fontFamily: '.SF Pro Display', fontWeight: FontWeight.bold, color: AppColors.textDisplay)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your email to receive a password reset link.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: _dialogInputDecoration('Email Address'),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (emailController.text.isEmpty) return;
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              final success = await authProvider.sendPasswordResetEmail(emailController.text.trim());
              if (ctx.mounted) {
                ctx.pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? 'Password reset email sent!' : authProvider.errorMessage ?? 'Error')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandStrong,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
            child: const Text('Send Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // [REF: OWNER_SIGNIN_DIALOG]
  /// Two steps in one dialog: address, then the code mailed to it.
  ///
  /// There is no password here and there is not meant to be. A generated
  /// temporary password would make the mailbox the real credential anyway,
  /// while adding a forced-change screen, a reset path and a lockout policy —
  /// and leaving a live credential sitting in an inbox.
  ///
  /// The step always advances after "Send code", whatever the server said.
  /// Only connectivity failures and rate limits are surfaced: the user can
  /// act on both. Everything else gets the same neutral sentence.
  void _showOwnerSignInDialog(BuildContext context) {
    final emailController = TextEditingController(text: _emailController.text);
    final codeController = TextEditingController();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Out here, not inside the builder: sendOwnerOtp notifies listeners, which
    // re-runs the builder, and state declared in it would reset mid-request
    // while the request's result landed in the discarded copy.
    bool codeSent = false;
    bool busy = false;
    String? inlineError;
    // Mirrors the server's per-address limit (smtp_max_frequency), so the button
    // is not offered during the window it would only be refused in.
    const resendCooldownSeconds = 60;
    int resendIn = 0;
    Timer? resendTimer;

    // Disposed when the dialog route finishes rather than in the State's
    // dispose: these two belong to the dialog, not to the screen, and the
    // screen can outlive several openings of it.
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> sendCode() async {
              final email = emailController.text.trim();
              if (!email.contains('@')) {
                setDialogState(() => inlineError = 'Enter a valid email address.');
                return;
              }
              setDialogState(() {
                busy = true;
                inlineError = null;
              });
              final ok = await authProvider.sendOwnerOtp(email);
              final message = authProvider.errorMessage;
              if (!ctx.mounted) return;
              setDialogState(() {
                busy = false;
                // Worth naming: the user can act on them, they tell an attacker
                // nothing, and "a code is on its way" would be false for both.
                if (!ok &&
                    message != null &&
                    (AuthService.looksLikeNetworkError(message) ||
                        message.startsWith('Too many'))) {
                  inlineError = message;
                } else {
                  codeSent = true;
                  // A new code replaces the old one, so a stale entry can only fail.
                  codeController.clear();
                  resendIn = resendCooldownSeconds;
                  resendTimer?.cancel();
                  resendTimer =
                      Timer.periodic(const Duration(seconds: 1), (timer) {
                    if (!ctx.mounted) {
                      timer.cancel();
                      return;
                    }
                    setDialogState(() {
                      resendIn--;
                      if (resendIn <= 0) timer.cancel();
                    });
                  });
                }
              });
            }

            Future<void> verify() async {
              setDialogState(() {
                busy = true;
                inlineError = null;
              });
              final ok = await authProvider.verifyOwnerOtp(
                emailController.text.trim(),
                codeController.text,
              );
              if (ok) {
                // [REF: OWNER_OTP_SCOPE]
                // signInWithOtp mails a code to any EXISTING account, so a
                // successful verify here proves control of the mailbox and
                // nothing about which kind of account it is. Without this
                // check the dialog would be a passwordless sign-in for
                // officers and admins too.
                //
                // Staff have passwords and the form above; an owner has only
                // this. So a non-owner session is ended rather than handed to
                // the router.
                //
                // Nothing here is gated on the dialog still being mounted: the
                // new session can make the router dismiss it, and that must not
                // skip the sign-out.
                final role = await authProvider.ensureRole();
                if (role != null && role != 'owner') {
                  await authProvider.signOut();
                  if (!ctx.mounted) return;
                  setDialogState(() {
                    busy = false;
                    // 'pending': the code created a fresh account, but no
                    // inspector has recorded this address on an establishment.
                    inlineError = role == 'pending'
                        ? 'No establishment is registered to this address yet. '
                            'Ask your inspector to record it on the next inspection.'
                        : 'That address belongs to a City Health Office staff '
                            'account. Sign in with your email and password above.';
                  });
                  return;
                }
                // The auth listener picks the session up and resolves the
                // role; the router does the rest.
                if (ctx.mounted) ctx.pop();
                return;
              }
              if (!ctx.mounted) return;
              setDialogState(() {
                busy = false;
                inlineError = authProvider.errorMessage ??
                    'That code did not work. Check it and try again.';
              });
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                codeSent ? 'Enter your code' : 'View your inspections',
                style: const TextStyle(
                    fontFamily: '.SF Pro Display',
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDisplay),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      codeSent
                          ? 'If ${emailController.text.trim()} is registered '
                              'with the City Health Office, a 6-digit code is '
                              'on its way. It expires shortly.'
                          : 'Enter the email address the City Health Office '
                              'has on record for your establishment. We will '
                              'send you a code — no password needed.',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    if (!codeSent)
                      TextField(
                        controller: emailController,
                        decoration: _dialogInputDecoration('Email Address'),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        enabled: !busy,
                      )
                    else
                      TextField(
                        controller: codeController,
                        decoration: _dialogInputDecoration('6-digit code'),
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        enabled: !busy,
                      ),
                    if (inlineError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        inlineError!,
                        style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontFamily: '.SF Pro Text'),
                      ),
                    ],
                    if (codeSent) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: busy || resendIn > 0 ? null : sendCode,
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32)),
                        child: Text(
                          resendIn > 0
                              ? 'Resend code in ${resendIn}s'
                              : 'Resend code',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setDialogState(() {
                                  codeSent = false;
                                  codeController.clear();
                                  inlineError = null;
                                }),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32)),
                        child: const Text(
                          'Use a different email',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actionsPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => ctx.pop(),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  onPressed: busy ? null : (codeSent ? verify : sendCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandStrong,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    elevation: 0,
                  ),
                  child: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(codeSent ? 'Sign In' : 'Send Code',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      resendTimer?.cancel();
      emailController.dispose();
      codeController.dispose();
    });
  }

  // [REF: SIGNUP_DIALOG]
  void _showSignUpDialog(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Create Account', style: TextStyle(fontFamily: '.SF Pro Display', fontWeight: FontWeight.bold, color: AppColors.textDisplay)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: _dialogInputDecoration('First Name'),
                  validator: (v) => v!.isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  decoration: _dialogInputDecoration('Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => !v!.contains('@') ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  decoration: _dialogInputDecoration('Password'),
                  obscureText: true,
                  validator: (v) => v!.length < 6 ? 'Min 6 characters' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmController,
                  decoration: _dialogInputDecoration('Confirm Password'),
                  obscureText: true,
                  validator: (v) => v != passwordController.text ? 'Passwords do not match' : null,
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              final success = await authProvider.signUpWithEmailPassword(
                emailController.text.trim(),
                passwordController.text,
                nameController.text.trim(),
              );
              if (ctx.mounted) {
                ctx.pop();
                if (success) {
                  // Supabase keeps the new account signed out until the
                  // verification link is clicked, so tell the user what
                  // comes next instead of waiting for a session.
                  //
                  // The activation sentence is not optional. A new account is
                  // 'pending' now (see [REF: PENDING_APPROVAL]) and can
                  // read nothing at all, so a message that stopped at "then
                  // sign in" would promise a working app and deliver an empty
                  // one.
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Account created! Verify your email, then ask an '
                          'administrator to activate your account.'),
                      duration: Duration(seconds: 6)));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authProvider.errorMessage ?? 'Error')));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandStrong,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
            child: const Text('Sign Up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
