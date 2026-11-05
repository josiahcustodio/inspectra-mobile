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

  // [REF: ROLE_STATE]
  /// This account's role, or null while unresolved. Null is "unknown", never
  /// "no access" — see [roleUnknown] for why the distinction is load-bearing.
  String? _role;

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

  // MFA enrollment requires a verified email. Email/password accounts
  // confirm via the sign-up link, and since confirmation is required
  // project-wide, a session without a confirmed email is rare (it can only
  // arise if the requirement was ever toggled off). The gate stays for that
  // case.
  bool get needsEmailVerification =>
      isAuthenticated && user!.emailConfirmedAt == null;

  String? get role => _role;

  /// Signed in, but which kind of account is not known yet.
  ///
  /// The router must not guess here. Treating unknown as "inspector" would
  /// march an establishment owner into TOTP enrollment; treating it as "owner"
  /// would send an inspector to a screen with none of their work on it. Both
  /// are worse than a spinner, so this pins to the splash.
  bool get roleUnknown => isAuthenticated && _role == null;

  /// An establishment's point person: read-only, and only for the
  /// establishments mapped to them in `establishment_contacts`.
  bool get isOwner => _role == 'owner';

  /// A brand-new account nobody has approved yet.
  ///
  /// Every policy denies 'pending', so this session can reach no data at all.
  /// It needs its own screen: without one, a new inspector lands on a home
  /// screen of empty lists with nothing explaining why.
  bool get isPendingApproval => _role == 'pending';

  AuthProvider() {
    _init();
  }

  // [REF: AUTH_STATE_LISTENER]
  void _init() {
    _authSub = AuthService.authStateChanges.listen((supa.AuthState state) async {
      final session = state.session;
      debugPrint('Auth state changed (${state.event}): '
          '${session?.user.id ?? "signed out"}');
      // gotrue's listFactors() calls refreshSession(), which emits
      // tokenRefreshed, which re-enters this listener: an infinite refresh
      // loop that ends in a 429 and a forced sign-out. A refreshed token
      // changes neither the role nor the MFA state, so there is nothing to
      // recompute here.
      if (state.event == AuthChangeEvent.tokenRefreshed) return;
      if (session != null) {
        // No ensureProfile() call any more: the handle_new_user() trigger
        // creates profiles/{uid} server-side the moment the auth user is
        // born, so there is nothing for the client to bootstrap.
        _needsAal2 = MfaService.needsAal2Upgrade;
        _hasTotpEnrolled = await MfaService.hasTotpEnrolled();
        // Fetched here rather than lazily at the first screen: every routing
        // decision below depends on it, so an unresolved role has to be a
        // state the router can see rather than a surprise mid-navigation.
        _role = await AuthService.fetchRole();
      } else {
        _needsAal2 = false;
        _hasTotpEnrolled = null;
        _role = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
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

  /// Re-reads the role, for the one case the auth listener cannot cover: an
  /// admin approving this account while the app sits on the pending screen.
  Future<void> refreshRole() async {
    if (!isAuthenticated) return;
    _role = await AuthService.fetchRole();
    notifyListeners();
  }

  /// Resolves the role if it is not known yet, and returns it. The splash
  /// awaits this before deciding where to send the session.
  Future<String?> ensureRole() async {
    if (!isAuthenticated) return null;
    if (_role == null) await refreshRole();
    return _role;
  }

  // [REF: OWNER_OTP_FLOW]
  /// Mails a sign-in code to an establishment's point person.
  Future<bool> sendOwnerOtp(String email) async {
    _setLoading(true);
    _setErrorMessage(null);
    try {
      await AuthService.sendOwnerOtp(email);
      return true;
    } catch (e) {
      _setErrorMessage(e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Exchanges the mailed code for a session. The auth listener picks the
  /// session up and resolves the role, so there is nothing to do on success
  /// but let the router react.
  Future<bool> verifyOwnerOtp(String email, String token) async {
    _setLoading(true);
    _setErrorMessage(null);
    try {
      return await AuthService.verifyOwnerOtp(email, token);
    } catch (e) {
      _setErrorMessage(e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
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
