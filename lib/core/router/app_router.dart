import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../ui/screens/login_screen.dart';
import '../../ui/screens/splash_sync_screen.dart';
import '../../ui/screens/main_navigation_screen.dart';
import '../../ui/screens/qr_scanner_screen.dart';
import '../../ui/screens/add_establishment_screen.dart';
import '../../ui/screens/mfa_enroll_screen.dart';
import '../../ui/screens/mfa_verify_screen.dart';
import '../../ui/screens/verify_email_screen.dart';

import '../../ui/screens/inspection_form_screen.dart';
import '../../ui/screens/inspection_details_screen.dart';
import '../../ui/screens/home_screen.dart';
import '../../ui/screens/establishments_screen.dart';
import '../../ui/screens/history_screen.dart';
import '../../ui/screens/profile_screen.dart';
import '../../data/models/establishment.dart';

// Global keys for navigation
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
final GlobalKey<NavigatorState> _shellNavigatorEstablishmentsKey = GlobalKey<NavigatorState>(debugLabel: 'shellEst');
final GlobalKey<NavigatorState> _shellNavigatorHistoryKey = GlobalKey<NavigatorState>(debugLabel: 'shellHist');
final GlobalKey<NavigatorState> _shellNavigatorProfileKey = GlobalKey<NavigatorState>(debugLabel: 'shellProf');

GoRouter createAppRouter(AuthProvider authProvider) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/sync',
    refreshListenable: authProvider,
    // [REF: AUTH_ROUTE_GUARD]
    redirect: (BuildContext context, GoRouterState state) {
      final bool isAuthenticated = authProvider.isAuthenticated;
      final String loc = state.matchedLocation;
      final bool isGoingToLogin = loc == '/login';
      final bool isGoingToMfaVerify = loc == '/mfa-verify';
      final bool isGoingToMfaEnroll = loc == '/mfa-enroll';
      final bool isGoingToVerifyEmail = loc == '/verify-email';

      // Unauthenticated: only /login and /mfa-verify are reachable.
      // /mfa-verify runs mid sign-in, while a MultiFactorResolver is
      // pending and currentUser is still null.
      if (!isAuthenticated) {
        // A second-factor challenge just came back (e.g. from the Google
        // popup flow) — push to /mfa-verify even if we're sitting on
        // /login, since nothing else triggers this navigation.
        if (authProvider.mfaChallengePending) {
          return isGoingToMfaVerify ? null : '/mfa-verify';
        }
        if (!isGoingToLogin && !isGoingToMfaVerify) return '/login';
        return null;
      }

      // Authenticated but sitting on /login or /mfa-verify: leave.
      if (isGoingToLogin || isGoingToMfaVerify) {
        return '/sync';
      }

      // Email not verified yet — required before MFA enrollment can even
      // be attempted. Check this before MFA status.
      if (authProvider.needsEmailVerification) {
        return isGoingToVerifyEmail ? null : '/verify-email';
      }
      if (isGoingToVerifyEmail) {
        return '/sync';
      }

      // MFA enrollment status not yet resolved (async check in flight) —
      // pin to /sync (already shows a loading UI) so /home never flashes
      // before bouncing back out.
      if (authProvider.mfaStatusUnknown) {
        return loc == '/sync' ? null : '/sync';
      }

      // No TOTP factor enrolled yet — force enrollment, no way around it.
      if (authProvider.requiresMfaEnrollment) {
        return isGoingToMfaEnroll ? null : '/mfa-enroll';
      }

      // Already enrolled but somehow on /mfa-enroll — leave.
      if (isGoingToMfaEnroll) {
        return '/sync';
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/sync',
        builder: (context, state) => const SplashSyncScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/mfa-enroll',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MfaEnrollScreen(),
      ),
      GoRoute(
        path: '/mfa-verify',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MfaVerifyScreen(),
      ),
      GoRoute(
        path: '/qr',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const QRScannerScreen(),
      ),
      GoRoute(
        path: '/establishments/add',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AddEstablishmentScreen(),
      ),
      GoRoute(
        path: '/establishments/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final est = state.extra as Establishment;
          return AddEstablishmentScreen(establishment: est);
        },
      ),
      GoRoute(
        path: '/inspection',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final est = state.extra as Establishment;
          return InspectionFormScreen(establishment: est);
        },
      ),
      GoRoute(
        path: '/inspection/details/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final logId = state.pathParameters['id']!;
          final establishmentName = state.extra as String? ?? 'Unknown';
          return InspectionDetailsScreen(
            logId: logId,
            establishmentName: establishmentName,
          );
        },
      ),
      
      // [REF: NAV_SHELL]
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell navigationShell) {
          return MainNavigationScreen(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            navigatorKey: _shellNavigatorHomeKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorEstablishmentsKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/establishments',
                builder: (context, state) => const EstablishmentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorHistoryKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorProfileKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
