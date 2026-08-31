import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Wraps Firebase Auth's TOTP (Google Authenticator-style) multi-factor
/// APIs, mirroring [AuthService]'s static-method/friendly-error style.
class MfaService {
  static const String _issuer = 'Inspectra';

  /// True if [user] already has a TOTP factor enrolled.
  static Future<bool> hasTotpEnrolled(User user) async {
    try {
      final factors = await user.multiFactor.getEnrolledFactors();
      return factors.whereType<TotpMultiFactorInfo>().isNotEmpty;
    } catch (e) {
      debugPrint('hasTotpEnrolled failed: $e');
      return false;
    }
  }

  /// Starts enrollment: opens a fresh MFA session and generates a TOTP secret.
  static Future<TotpSecret> startEnrollment(User user) async {
    try {
      final session = await user.multiFactor.getSession();
      return await TotpMultiFactorGenerator.generateSecret(session);
    } on FirebaseAuthException catch (e) {
      debugPrint('startEnrollment FirebaseAuthException: ${e.code}');
      throw _friendlyMfaError(e);
    } catch (e) {
      debugPrint('startEnrollment failed: $e');
      throw Exception('Could not start authenticator setup. Please try again.');
    }
  }

  /// Builds the `otpauth://` URL for rendering the enrollment QR code.
  static Future<String> buildQrUrl(TotpSecret secret,
      {required String accountName}) {
    return secret.generateQrCodeUrl(accountName: accountName, issuer: _issuer);
  }

  /// Verifies [code] against [secret] and enrolls it as the user's second factor.
  static Future<void> completeEnrollment({
    required User user,
    required TotpSecret secret,
    required String code,
    String displayName = 'Authenticator App',
  }) async {
    try {
      final assertion =
          await TotpMultiFactorGenerator.getAssertionForEnrollment(secret, code);
      await user.multiFactor.enroll(assertion, displayName: displayName);
    } on FirebaseAuthException catch (e) {
      debugPrint('completeEnrollment FirebaseAuthException: ${e.code}');
      throw _friendlyMfaError(e);
    } catch (e) {
      debugPrint('completeEnrollment failed: $e');
      throw Exception('Could not verify code. Please try again.');
    }
  }

  /// Resolves an in-progress sign-in using [resolver] and the entered [code].
  static Future<UserCredential> completeSignIn({
    required MultiFactorResolver resolver,
    required String code,
  }) async {
    try {
      final totpHints = resolver.hints.whereType<TotpMultiFactorInfo>();
      final hint = totpHints.isEmpty ? null : totpHints.first;
      if (hint == null) {
        throw Exception('No authenticator app is set up for this account.');
      }
      final assertion =
          await TotpMultiFactorGenerator.getAssertionForSignIn(hint.uid, code);
      return await resolver.resolveSignIn(assertion);
    } on FirebaseAuthException catch (e) {
      debugPrint('completeSignIn FirebaseAuthException: ${e.code}');
      throw _friendlyMfaError(e);
    }
  }

  /// Removes the currently enrolled TOTP factor, e.g. before re-enrolling
  /// on a new device.
  static Future<void> resetAuthenticator(User user) async {
    try {
      final factors = await user.multiFactor.getEnrolledFactors();
      final totpFactors = factors.whereType<TotpMultiFactorInfo>();
      if (totpFactors.isEmpty) return;
      final totp = totpFactors.first;
      await user.multiFactor.unenroll(factorUid: totp.uid);
    } on FirebaseAuthException catch (e) {
      debugPrint('resetAuthenticator FirebaseAuthException: ${e.code}');
      throw _friendlyMfaError(e);
    } catch (e) {
      debugPrint('resetAuthenticator failed: $e');
      throw Exception('Could not reset authenticator. Please try again.');
    }
  }

  static Exception _friendlyMfaError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return Exception('Incorrect code. Please try again.');
      case 'requires-recent-login':
        return Exception(
            'Your session has expired. Please sign out and sign in again to continue.');
      case 'second-factor-already-in-use':
        return Exception('This authenticator is already registered.');
      case 'network-request-failed':
        return Exception('No internet connection. Please check your network.');
      case 'operation-not-allowed':
        return Exception(
            'Two-factor authentication is not enabled for this project.');
      default:
        return Exception('Something went wrong. Please try again.');
    }
  }
}
