import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_service.dart';

class AuthService {
  static GoTrueClient get _auth => Supabase.instance.client.auth;

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
    await _auth.signOut();
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

  /// Stamped on every inspection as `inspector_name`, so it is the name
  /// printed on Sanitary Orders. Metadata only: `profiles` has no name column.
  static Future<void> updateDisplayName(String name) async {
    await _auth.updateUser(UserAttributes(data: {'display_name': name.trim()}));
  }

  static String? get photoUrl =>
      _auth.currentUser?.userMetadata?['avatar_url'] as String?;

  static bool get emailVerified =>
      _auth.currentUser?.emailConfirmedAt != null;

  static Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  // [REF: OWNER_OTP_SIGNIN]
  /// Mails a six-digit code to an establishment's point person.
  ///
  /// `shouldCreateUser: false` stops this path from CREATING accounts. Left at
  /// its default of true, anyone who typed an address into the owner dialog
  /// would mint themselves one — so only addresses an admin has already
  /// provisioned (see the provision-owner function) can receive a code.
  ///
  /// It does NOT make the path owner-only, and it must not be read that way:
  /// a code is mailed to ANY existing account, staff included, so on its own
  /// this would be a passwordless sign-in for the whole project. The dialog
  /// closes that by checking the role once the session exists and signing a
  /// non-owner straight back out — see the owner sign-in dialog in
  /// login_screen.dart. (Mailbox access already implied account takeover via
  /// the password-reset link, so this is not a new exposure; it is still not
  /// a door worth leaving wider than it has to be.)
  /// Note that GoTrue does NOT hide the outcome: with shouldCreateUser false
  /// an unknown address comes back as an `otp_disabled` error, which would
  /// turn this dialog into a way to test whether a given business owner has an
  /// account. Hiding that is the caller's job — see the owner sign-in dialog
  /// in login_screen.dart, which advances to the code step either way and only
  /// surfaces genuine connectivity failures.
  ///
  /// There is no password anywhere in this flow. A generated temporary
  /// password would have made the mailbox the real credential anyway, while
  /// adding a forced-change screen, a reset path and a lockout policy to
  /// maintain — and leaving a live credential sitting in an inbox.
  static Future<void> sendOwnerOtp(String email) async {
    try {
      await _auth.signInWithOtp(email: email, shouldCreateUser: false);
    } on AuthException catch (e) {
      debugPrint('sendOwnerOtp AuthException: ${e.code} ${e.message}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('sendOwnerOtp error: $e');
      throw Exception('Could not send the code. Check your connection and try again.');
    }
  }

  /// Exchanges the mailed code for a session.
  ///
  /// OtpType.email, not .magiclink: signInWithOtp on an existing user issues a
  /// login code, and verifying it under the wrong type fails with a token
  /// mismatch that reads like a typo to the user.
  static Future<bool> verifyOwnerOtp(String email, String token) async {
    try {
      final res = await _auth.verifyOTP(
        email: email,
        token: token.trim(),
        type: OtpType.email,
      );
      return res.session != null;
    } on AuthException catch (e) {
      debugPrint('verifyOwnerOtp AuthException: ${e.code} ${e.message}');
      throw _friendlyAuthError(e);
    } catch (e) {
      debugPrint('verifyOwnerOtp error: $e');
      throw Exception('Could not verify the code. Check your connection and try again.');
    }
  }

  // [REF: ROLE_LOOKUP]
  /// This account's role from `profiles`, or null if it cannot be read.
  ///
  /// The app had no role awareness at all before owners existed — every
  /// signed-in user was an inspector. It reads the row rather than a JWT
  /// claim because the role is not in the token, and `profiles_select`
  /// (`id = auth.uid() or is_admin()`) already permits exactly this one row.
  ///
  /// Null means "unknown", never "no access": a failed lookup must not be
  /// mistaken for a role, which is why the router pins an unresolved role to
  /// the splash rather than guessing a destination.
  ///
  // [REF: ROLE_CACHE]
  /// Which is also why the answer is CACHED. This is a live network read, and
  /// the router pins an unknown role to /sync — so offline, the first version
  /// of this method deadlocked the app: null role, pinned to /sync, splash
  /// finishes, `context.go('/home')` redirects straight back to /sync, a fresh
  /// splash runs initState, forever. An inspector could no longer reach the
  /// Hive cache the whole offline-first design exists for, which is the one
  /// state this app must survive.
  ///
  /// A role is a slow-moving fact about an account, so the last known value is
  /// the right answer when the network cannot supply a fresher one. It is
  /// written only on a successful read and only for the account it belongs to
  /// (see OfflineService.rolePrefKey), and a successful read always wins — a
  /// demotion lands the first time the device is online.
  static Future<String?> fetchRole() async {
    final uid = _auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      final role = row?['role'] as String?;
      if (role != null) {
        await OfflineService.writePref(OfflineService.rolePrefKey(uid), role);
      }
      return role;
    } catch (e) {
      // Offline, or RLS/MFA refused the read. Fall back to what this device
      // last saw for THIS account; null if it has never seen one, which keeps
      // the honest "unknown" state for a first sign-in with no signal.
      final cached = OfflineService.readPref(OfflineService.rolePrefKey(uid));
      debugPrint('Role lookup failed ($e); cached role: ${cached ?? "none"}');
      return cached;
    }
  }

  // ensureProfile() is gone, on purpose. It existed as the client-side
  // stand-in for the Supabase handle_new_user() trigger this app relied on
  // before the Firebase migration — that trigger exists again
  // (migration/sql/01_schema.sql), so profiles/{uid} rows are created
  // server-side the moment the auth user is born and no client write is
  // needed or allowed to be load-bearing.

  /// Connectivity failures reach us as AuthExceptions with NO stable code
  /// (supabase's retryable-fetch errors carry only prose), so a substring
  /// heuristic is the best available signal. One list, shared with
  /// MfaService, so the two sides can never drift apart again — this is the
  /// union of what each matched separately before the consolidation.
  static bool looksLikeNetworkError(String message) {
    final m = message.toLowerCase();
    return m.contains('socket') ||
        m.contains('network') ||
        m.contains('failed host lookup');
  }

  /// Maps AuthException error codes to clean, user-facing messages.
  // [REF: AUTH_ERROR_MESSAGES]
  static Exception _friendlyAuthError(AuthException e) {
    switch (e.code) {
      case 'invalid_credentials':
        return Exception('Incorrect email or password.');
      case 'otp_expired':
        return Exception(
            'That code is wrong or has expired. Check it, or request a new one.');
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
        if (looksLikeNetworkError(e.message)) {
          return Exception('No internet connection. Please check your network.');
        }
        return Exception('Authentication failed. Please try again.');
    }
  }
}
