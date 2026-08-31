import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb
        ? '627591929126-0a99t9v3sdhpngu0obag0htr70jvqorf.apps.googleusercontent.com'
        : null,
  );

  /// Signs in the user with Google.
  /// Returns true on success, false on failure.
  static Future<bool> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        await _auth.signInWithPopup(googleProvider);
        return true;
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          // User cancelled — not an error
          return false;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await _auth.signInWithCredential(credential);
        return true;
      }
    } on FirebaseAuthMultiFactorException {
      // Preserve e.resolver — handled one layer up in AuthProvider.
      rethrow;
    } on FirebaseAuthException catch (e) {
      debugPrint('Google Sign-In FirebaseAuthException: ${e.code}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      throw Exception('Sign-in failed. Please try again.');
    }
  }

  static Future<bool> signInWithEmailPassword(
      String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return true;
    } on FirebaseAuthMultiFactorException {
      // Preserve e.resolver — handled one layer up in AuthProvider.
      rethrow;
    } on FirebaseAuthException catch (e) {
      debugPrint('Email/Pass FirebaseAuthException: ${e.code}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Login Error (Email/Pass): $e');
      throw Exception('Sign-in failed. Please try again.');
    }
  }

  static Future<bool> signUpWithEmailPassword(
      String email, String password, String firstName) async {
    try {
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      if (cred.user != null) {
        await cred.user!.updateDisplayName(firstName);
        // MFA enrollment requires a verified email — send it right away.
        await cred.user!.sendEmailVerification();
      }
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Register FirebaseAuthException: ${e.code}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Register Error: $e');
      throw Exception('Registration failed. Please try again.');
    }
  }

  /// Resends the verification email to the current user.
  static Future<bool> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      await user.sendEmailVerification();
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Send Verification Email FirebaseAuthException: ${e.code}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Send Verification Email Error: $e');
      throw Exception('Could not send verification email. Please try again.');
    }
  }

  /// Reloads the current user from Firebase so [User.emailVerified]
  /// reflects whether they've clicked the verification link yet.
  static Future<bool> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      return true;
    } catch (e) {
      debugPrint('Reload user failed: $e');
      return false;
    }
  }

  static Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Password Reset FirebaseAuthException: ${e.code}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Password Reset Error: $e');
      throw Exception('Failed to send reset email. Please try again.');
    }
  }

  static Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Ensures a `profiles/{uid}` doc exists for [user], defaulting to role
  /// 'officer'. This is the client-side stand-in for the Supabase
  /// `handle_new_user()` trigger this app relied on before the Firebase
  /// migration (see supabase/migrations/20260625171500_auth_roles.sql in
  /// inspectra-web) — there is no Cloud Function yet, so this runs on every
  /// sign-in and is a no-op once the profile already exists.
  ///
  /// Matches firestore.rules: a user may only ever self-create their OWN
  /// profile with role 'officer' — never 'admin'. Returns the resolved role.
  static Future<String> ensureProfile(User user) async {
    final ref = FirebaseFirestore.instance.collection('profiles').doc(user.uid);
    try {
      final snap = await ref.get();
      if (snap.exists) {
        return (snap.data()?['role'] as String?) ?? 'officer';
      }
      await ref.set({
        'role': 'officer',
        'email': user.email,
        'created_at': DateTime.now().toIso8601String(),
      });
      return 'officer';
    } catch (e) {
      debugPrint('ensureProfile failed: $e');
      return 'officer';
    }
  }

  /// Maps FirebaseAuthException error codes to clean, user-facing messages.
  static Exception _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return Exception('Incorrect email or password.');
      case 'user-disabled':
        return Exception('This account has been disabled. Contact your administrator.');
      case 'too-many-requests':
        return Exception('Too many failed attempts. Please try again later.');
      case 'network-request-failed':
        return Exception('No internet connection. Please check your network.');
      case 'email-already-in-use':
        return Exception('An account with this email already exists.');
      case 'weak-password':
        return Exception('Password is too weak. Use at least 6 characters.');
      case 'invalid-email':
        return Exception('The email address is not valid.');
      case 'operation-not-allowed':
        return Exception('This sign-in method is not enabled.');
      default:
        return Exception('Authentication failed. Please try again.');
    }
  }
}
