import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';

class AuthService {
  static GoTrueClient get _auth => Supabase.instance.client.auth;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // The WEB client id of the Google project Supabase's provider is
    // configured with — passed as serverClientId so the idToken's audience
    // is one Supabase accepts. See SupabaseConfig for the why.
    serverClientId: kIsWeb ? null : SupabaseConfig.googleServerClientId,
    clientId: kIsWeb ? SupabaseConfig.googleServerClientId : null,
  );

  /// Signs in the user with Google.
  /// Returns true on success, false on failure (e.g. the user cancelled).
  ///
  /// No multi-factor exception path any more: Supabase always lands the
  /// sign-in at AAL1, and AuthProvider decides from the session's assurance
  /// level whether a TOTP challenge is still owed.
  // [REF: AUTH_SIGNIN_GOOGLE]
  static Future<bool> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web redirect flow — the browser leaves and comes back signed in.
        await _auth.signInWithOAuth(OAuthProvider.google);
        return true;
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          // User cancelled — not an error
          return false;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final idToken = googleAuth.idToken;
        if (idToken == null) {
          throw Exception(
              'Google did not return an ID token. Check the serverClientId configuration.');
        }

        await _auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: googleAuth.accessToken,
        );
        return true;
      }
    } on AuthException catch (e) {
      debugPrint('Google Sign-In AuthException: ${e.code} ${e.message}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      throw Exception('Sign-in failed. Please try again.');
    }
  }

  // [REF: AUTH_SIGNIN_EMAIL]
  static Future<bool> signInWithEmailPassword(
      String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
      return true;
    } on AuthException catch (e) {
      debugPrint('Email/Pass AuthException: ${e.code} ${e.message}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Login Error (Email/Pass): $e');
      throw Exception('Sign-in failed. Please try again.');
    }
  }

  // [REF: AUTH_SIGNUP_EMAIL]
  /// Creates the account. UNLIKE the Firebase era this does NOT sign the new
  /// user in: email confirmation is required project-wide, so Supabase parks
  /// the account (no session) until the link in the verification email is
  /// clicked. The caller should tell the user to check their inbox and then
  /// sign in. The profiles row is created server-side by the
  /// handle_new_user() trigger the moment the auth user exists.
  static Future<bool> signUpWithEmailPassword(
      String email, String password, String firstName) async {
    try {
      await _auth.signUp(
        email: email,
        password: password,
        data: {'display_name': firstName},
      );
      return true;
    } on AuthException catch (e) {
      debugPrint('Register AuthException: ${e.code} ${e.message}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Register Error: $e');
      throw Exception('Registration failed. Please try again.');
    }
  }

  /// Resends the verification email to the current user.
  static Future<bool> sendEmailVerification() async {
    try {
      final email = _auth.currentUser?.email;
      if (email == null) return false;
      await _auth.resend(type: OtpType.signup, email: email);
      return true;
    } on AuthException catch (e) {
      debugPrint('Send Verification Email AuthException: ${e.code}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('Send Verification Email Error: $e');
      throw Exception('Could not send verification email. Please try again.');
    }
  }

  /// Refreshes the current user from the auth server so
  /// [User.emailConfirmedAt] reflects whether they've clicked the
  /// verification link yet.
  static Future<bool> reloadCurrentUser() async {
    if (_auth.currentUser == null) return false;
    try {
      await _auth.getUser();
      return true;
    } catch (e) {
      debugPrint('Reload user failed: $e');
      return false;
    }
  }

  static Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _auth.resetPasswordForEmail(email);
      return true;
    } on AuthException catch (e) {
      debugPrint('Password Reset AuthException: ${e.code}');
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

  /// The display name recorded at sign-up (or by Google), read from user
  /// metadata — Supabase has no top-level displayName field.
  static String? get displayName {
    final meta = _auth.currentUser?.userMetadata;
    final name = (meta?['display_name'] ?? meta?['full_name'] ?? meta?['name'])
        as String?;
    return (name == null || name.isEmpty) ? null : name;
  }

  static String? get photoUrl =>
      _auth.currentUser?.userMetadata?['avatar_url'] as String?;

  static bool get emailVerified =>
      _auth.currentUser?.emailConfirmedAt != null;

  static Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  // ensureProfile() is gone, on purpose. It existed as the client-side
  // stand-in for the Supabase handle_new_user() trigger this app relied on
  // before the Firebase migration — that trigger exists again
  // (migration/sql/01_schema.sql), so profiles/{uid} rows are created
  // server-side the moment the auth user is born and no client write is
  // needed or allowed to be load-bearing.

  /// Maps AuthException error codes to clean, user-facing messages.
  // [REF: AUTH_ERROR_MESSAGES]
  static Exception _friendlyAuthError(AuthException e) {
    switch (e.code) {
      case 'invalid_credentials':
        return Exception('Incorrect email or password.');
      case 'email_not_confirmed':
        return Exception(
            'Your email is not verified yet. Check your inbox for the verification link, then sign in again.');
      case 'user_banned':
        return Exception(
            'This account has been disabled. Contact your administrator.');
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return Exception('Too many attempts. Please try again later.');
      case 'user_already_exists':
      case 'email_exists':
        return Exception('An account with this email already exists.');
      case 'weak_password':
        return Exception('Password is too weak. Use at least 6 characters.');
      case 'validation_failed':
        return Exception('The email address is not valid.');
      case 'provider_disabled':
        return Exception('This sign-in method is not enabled.');
      default:
        // Network failures surface as a generic AuthRetryableFetchException
        // with no code — give the connectivity hint when that happens.
        if (e.message.toLowerCase().contains('socket') ||
            e.message.toLowerCase().contains('network') ||
            e.message.toLowerCase().contains('failed host lookup')) {
          return Exception('No internet connection. Please check your network.');
        }
        return Exception('Authentication failed. Please try again.');
    }
  }
}
