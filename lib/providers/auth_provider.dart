import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as supa show AuthState;

import '../data/services/auth_service.dart';
import '../data/services/mfa_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  /// True when the session is signed in at AAL1 but the account has a
  /// verified TOTP factor — the second factor is still owed. Replaces the
  /// Firebase-era MultiFactorResolver: Supabase has no mid-sign-in limbo,
  /// the session exists and the restrictive RLS policies block its data
  /// access until the code upgrades it to AAL2.
  bool _needsAal2 = false;

  bool? _hasTotpEnrolled; // null = unknown/loading, false = needs enrollment
  StreamSubscription<supa.AuthState>? _authSub;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  User? get user => AuthService.currentUser;
  bool get isAuthenticated => user != null;

  /// Kept under its historical name — the router and MfaVerifyScreen key off
  /// it — but it now means "signed in, TOTP code still owed this session".
  bool get mfaChallengePending => isAuthenticated && _needsAal2;
  bool? get hasTotpEnrolled => _hasTotpEnrolled;
  bool get requiresMfaEnrollment => isAuthenticated && _hasTotpEnrolled == false;
  bool get mfaStatusUnknown => isAuthenticated && _hasTotpEnrolled == null;

  // MFA enrollment requires a verified email. Google sign-in accounts are
  // already verified by Google; email/password accounts confirm via the
  // sign-up link — and since confirmation is required project-wide, a
  // session without a confirmed email is rare (it can only arise if the
  // requirement was ever toggled off). The gate stays for that case.
  bool get needsEmailVerification =>
      isAuthenticated && user!.emailConfirmedAt == null;

  AuthProvider() {
    _init();
  }

  // [REF: AUTH_STATE_LISTENER]
  void _init() {
    _authSub = AuthService.authStateChanges.listen((supa.AuthState state) async {
      final session = state.session;
      debugPrint('Auth state changed (${state.event}): '
          '${session?.user.id ?? "signed out"}');
      if (session != null) {
        // No ensureProfile() call any more: the handle_new_user() trigger
        // creates profiles/{uid} server-side the moment the auth user is
        // born, so there is nothing for the client to bootstrap.
        _needsAal2 = MfaService.needsAal2Upgrade;
        _hasTotpEnrolled = await MfaService.hasTotpEnrolled();
      } else {
        _needsAal2 = false;
        _hasTotpEnrolled = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _setErrorMessage(null);

    try {
      final success = await AuthService.signInWithGoogle();
      return success;
    } catch (e) {
      _setErrorMessage(e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signInWithEmailPassword(String email, String password) async {
    _setLoading(true);
    _setErrorMessage(null);

    try {
      final success = await AuthService.signInWithEmailPassword(email, password);
      // If a TOTP factor is enrolled the session arrives at AAL1 and the
      // auth listener flips mfaChallengePending; the router then routes to
      // /mfa-verify. Nothing to catch here.
      return success;
    } catch (e) {
      _setErrorMessage(e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> completeMfaSignIn(String code) async {
    _setLoading(true);
    _setErrorMessage(null);

    try {
      await MfaService.completeSignIn(code: code);
      _needsAal2 = false;
      return true;
    } catch (e) {
      _setErrorMessage(e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Abandons the pending TOTP challenge. The half-authenticated AAL1
  /// session must not linger (it holds a working refresh token), so this
  /// signs out of it entirely.
  Future<void> cancelMfaChallenge() async {
    await signOut();
  }

  Future<void> refreshMfaStatus() async {
    if (!isAuthenticated) return;
    _needsAal2 = MfaService.needsAal2Upgrade;
    _hasTotpEnrolled = await MfaService.hasTotpEnrolled();
    notifyListeners();
  }

  Future<bool> resendVerificationEmail() async {
    _setLoading(true);
    _setErrorMessage(null);
    try {
      return await AuthService.sendEmailVerification();
    } catch (e) {
      _setErrorMessage(e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Reloads the current user and notifies listeners so the router can
  /// react once [needsEmailVerification] flips to false.
  Future<void> refreshEmailVerified() async {
    await AuthService.reloadCurrentUser();
    notifyListeners();
  }

  Future<bool> signUpWithEmailPassword(String email, String password, String firstName) async {
    _setLoading(true);
    _setErrorMessage(null);

    try {
      final success = await AuthService.signUpWithEmailPassword(email, password, firstName);
      return success;
    } catch (e) {
      _setErrorMessage(e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    _setLoading(true);
    _setErrorMessage(null);

    try {
      final success = await AuthService.sendPasswordResetEmail(email);
      return success;
    } catch (e) {
      _setErrorMessage(e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    _setLoading(true);
    try {
      await AuthService.signOut();
    } catch (e) {
      _setErrorMessage(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setErrorMessage(String? message) {
    _errorMessage = message;
    notifyListeners();
  }
}
