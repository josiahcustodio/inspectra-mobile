import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// One in-progress TOTP enrollment: the factor Supabase minted plus what the
/// user needs to register it — the otpauth:// URI for the QR code and the
/// base32 secret for manual entry. Replaces Firebase's TotpSecret.
class TotpEnrollment {
  final String factorId;
  final String secret;
  final String uri;
  const TotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
  });
}

/// Wraps Supabase Auth's TOTP (Google Authenticator-style) multi-factor
/// APIs, mirroring [AuthService]'s static-method/friendly-error style.
///
/// The model shift from Firebase: there is no mid-sign-in resolver limbo.
/// A session always exists first (AAL1); enrolling or verifying a factor
/// upgrades that same session to AAL2. "Signed in but second factor still
/// owed" is a property of the session, which AuthProvider reads via
/// getAuthenticatorAssuranceLevel().
class MfaService {
  static GoTrueClient get _auth => Supabase.instance.client.auth;

  /// True if the current user already has a verified TOTP factor.
  static Future<bool> hasTotpEnrolled() async {
    try {
      final res = await _auth.mfa.listFactors();
      return res.totp.any((f) => f.status == FactorStatus.verified);
    } catch (e) {
      debugPrint('hasTotpEnrolled failed: $e');
      return false;
    }
  }

  /// True when the session is AAL1 but the account can reach AAL2 — i.e. a
  /// verified factor exists and this session has not presented it yet.
  /// Synchronous: computed from the session JWT and its factor list.
  static bool get needsAal2Upgrade {
    try {
      final level = _auth.mfa.getAuthenticatorAssuranceLevel();
      return level.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
          level.nextLevel == AuthenticatorAssuranceLevels.aal2;
    } catch (e) {
      debugPrint('needsAal2Upgrade failed: $e');
      return false;
    }
  }

  /// Starts enrollment: mints a new TOTP factor and returns its QR URI and
  /// manual secret. Any unverified leftover from an abandoned attempt is
  /// unenrolled first — Supabase keeps those around, and a second enroll
  /// against a stale one fails.
  // [REF: MFA_ENROLL_START]
  static Future<TotpEnrollment> startEnrollment() async {
    try {
      final existing = await _auth.mfa.listFactors();
      for (final factor in existing.all) {
        if (factor.factorType == FactorType.totp &&
            factor.status == FactorStatus.unverified) {
          await _auth.mfa.unenroll(factor.id);
        }
      }

      final res = await _auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'Inspectra',
        friendlyName: 'Authenticator App',
      );
      final totp = res.totp;
      if (totp == null) {
        throw Exception('Could not start authenticator setup. Please try again.');
      }
      return TotpEnrollment(
        factorId: res.id,
        secret: totp.secret,
        uri: totp.uri,
      );
    } on AuthException catch (e) {
      debugPrint('startEnrollment AuthException: ${e.code} ${e.message}');
      throw _friendlyMfaError(e);
    } catch (e) {
      debugPrint('startEnrollment failed: $e');
      throw Exception('Could not start authenticator setup. Please try again.');
    }
  }

  /// Verifies [code] against the enrolling factor, completing enrollment.
  /// Side effect worth knowing: the verify also upgrades THIS session to
  /// AAL2, so no separate challenge follows a fresh enrollment.
  // [REF: MFA_ENROLL_CONFIRM]
  static Future<void> completeEnrollment({
    required String factorId,
    required String code,
  }) async {
    try {
      final challenge = await _auth.mfa.challenge(factorId: factorId);
      await _auth.mfa.verify(
        factorId: factorId,
        challengeId: challenge.id,
        code: code,
      );
    } on AuthException catch (e) {
      debugPrint('completeEnrollment AuthException: ${e.code} ${e.message}');
      throw _friendlyMfaError(e);
    } catch (e) {
      debugPrint('completeEnrollment failed: $e');
      throw Exception('Could not verify code. Please try again.');
    }
  }

  /// Presents [code] for the account's verified TOTP factor, upgrading the
  /// current AAL1 session to AAL2. The sign-in-time challenge.
  // [REF: MFA_SIGNIN_CHALLENGE]
  static Future<void> completeSignIn({required String code}) async {
    try {
      final factors = await _auth.mfa.listFactors();
      final verified = factors.totp.where((f) => f.status == FactorStatus.verified);
      if (verified.isEmpty) {
        throw Exception('No authenticator app is set up for this account.');
      }
      final factor = verified.first;
      final challenge = await _auth.mfa.challenge(factorId: factor.id);
      await _auth.mfa.verify(
        factorId: factor.id,
        challengeId: challenge.id,
        code: code,
      );
    } on AuthException catch (e) {
      debugPrint('completeSignIn AuthException: ${e.code} ${e.message}');
      throw _friendlyMfaError(e);
    }
  }

  /// Removes the currently enrolled TOTP factor, e.g. before re-enrolling
  /// on a new device. Requires an AAL2 session — which every fully signed-in
  /// mobile session is, since enrollment is mandatory here.
  static Future<void> resetAuthenticator() async {
    try {
      final factors = await _auth.mfa.listFactors();
      for (final factor in factors.all) {
        if (factor.factorType == FactorType.totp) {
          await _auth.mfa.unenroll(factor.id);
        }
      }
    } on AuthException catch (e) {
      debugPrint('resetAuthenticator AuthException: ${e.code} ${e.message}');
      throw _friendlyMfaError(e);
    } catch (e) {
      debugPrint('resetAuthenticator failed: $e');
      throw Exception('Could not reset authenticator. Please try again.');
    }
  }

  static Exception _friendlyMfaError(AuthException e) {
    switch (e.code) {
      case 'mfa_verification_failed':
        return Exception('Incorrect code. Please try again.');
      case 'insufficient_aal':
        return Exception(
            'Your session has expired. Please sign out and sign in again to continue.');
      case 'mfa_factor_name_conflict':
        return Exception('This authenticator is already registered.');
      case 'too_many_enrolled_mfa_factors':
        return Exception(
            'This account already has the maximum number of authenticators.');
      case 'mfa_totp_enroll_not_enabled':
      case 'mfa_totp_verify_not_enabled':
        return Exception(
            'Two-factor authentication is not enabled for this project.');
      default:
        if (e.message.toLowerCase().contains('invalid totp code')) {
          return Exception('Incorrect code. Please try again.');
        }
        if (AuthService.looksLikeNetworkError(e.message)) {
          return Exception('No internet connection. Please check your network.');
        }
        return Exception('Something went wrong. Please try again.');
    }
  }
}
