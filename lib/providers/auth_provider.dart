import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../data/services/auth_service.dart';
import '../data/services/mfa_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  MultiFactorResolver? _mfaResolver;
  bool? _hasTotpEnrolled; // null = unknown/loading, false = needs enrollment

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  User? get user => AuthService.currentUser;
  bool get isAuthenticated => user != null;

  MultiFactorResolver? get mfaResolver => _mfaResolver;
  bool get mfaChallengePending => _mfaResolver != null;
  bool? get hasTotpEnrolled => _hasTotpEnrolled;
  bool get requiresMfaEnrollment => isAuthenticated && _hasTotpEnrolled == false;
  bool get mfaStatusUnknown => isAuthenticated && _hasTotpEnrolled == null;

  // MFA enrollment requires a verified email. Google sign-in accounts are
  // already verified by Google; email/password accounts must click the
  // link sent on sign-up.
  bool get needsEmailVerification => isAuthenticated && user!.emailVerified == false;

  AuthProvider() {
    _init();
  }

  // [REF: AUTH_STATE_LISTENER]
  void _init() {
    // Listen to Firebase auth state changes
    AuthService.authStateChanges.listen((User? firebaseUser) async {
      debugPrint('Firebase Auth State Changed: ${firebaseUser?.uid ?? "signed out"}');
      _mfaResolver = null;
      if (firebaseUser != null) {
        // Return value deliberately discarded. The role it resolves is not
        // read anywhere in this app — every authorisation decision on mobile
        // is made by firestore.rules, not by the client. The call itself is
        // load-bearing and must stay: it CREATES the profiles/{uid} document
        // those rules key off, so dropping it would lock a new inspector out
        // of their own data on first sign-in.
        await AuthService.ensureProfile(firebaseUser);
        _hasTotpEnrolled = await MfaService.hasTotpEnrolled(firebaseUser);
      } else {
        _hasTotpEnrolled = null;
      }
      notifyListeners();
    });
  }

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _setErrorMessage(null);

    try {
      final success = await AuthService.signInWithGoogle();
      return success;
    } on FirebaseAuthMultiFactorException catch (e) {
      _mfaResolver = e.resolver;
      return false;
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
      return success;
    } on FirebaseAuthMultiFactorException catch (e) {
      _mfaResolver = e.resolver;
      return false;
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
      final resolver = _mfaResolver;
      if (resolver == null) {
        throw Exception('Verification session expired. Please sign in again.');
      }
      await MfaService.completeSignIn(resolver: resolver, code: code);
      _mfaResolver = null;
      return true;
    } catch (e) {
      _setErrorMessage(e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void cancelMfaChallenge() {
    _mfaResolver = null;
    notifyListeners();
  }

  Future<void> refreshMfaStatus() async {
    final u = user;
    if (u == null) return;
    _hasTotpEnrolled = await MfaService.hasTotpEnrolled(u);
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
