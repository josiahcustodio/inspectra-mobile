import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../ui/screens/login_screen.dart';
import '../../ui/screens/splash_sync_screen.dart';
import '../../ui/screens/main_navigation_screen.dart';
import '../../ui/screens/mfa_enroll_screen.dart';
import '../../ui/screens/mfa_verify_screen.dart';
import '../../ui/screens/verify_email_screen.dart';
import '../../ui/screens/owner_home_screen.dart';
import '../../ui/screens/pending_approval_screen.dart';
import '../../ui/screens/set_password_screen.dart';

import '../../ui/screens/inspection_form_screen.dart';
import '../../ui/screens/inspection_details_screen.dart';
import '../../ui/screens/home_screen.dart';
import '../../ui/screens/establishments_screen.dart';
import '../../ui/screens/map_screen.dart';
import '../../ui/screens/history_screen.dart';
import '../../ui/screens/profile_screen.dart';
import '../../data/models/establishment.dart';

// Global keys for navigation
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
final GlobalKey<NavigatorState> _shellNavigatorEstablishmentsKey = GlobalKey<NavigatorState>(debugLabel: 'shellEst');
final GlobalKey<NavigatorState> _shellNavigatorHistoryKey = GlobalKey<NavigatorState>(debugLabel: 'shellHist');
final GlobalKey<NavigatorState> _shellNavigatorProfileKey = GlobalKey<NavigatorState>(debugLabel: 'shellProfile');
final GlobalKey<NavigatorState> _shellNavigatorMapKey = GlobalKey<NavigatorState>(debugLabel: 'shellMap');

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
      final bool isGoingToPending = loc == '/pending-approval';
      final bool isGoingToOwner = loc.startsWith('/my');

      // Unauthenticated: only /login is reachable. (Under Supabase there is
      // no pre-session MFA state — the Firebase resolver limbo is gone; a
      // second-factor challenge now happens on an existing AAL1 session.)
      if (!isAuthenticated) {
        if (!isGoingToLogin) return '/login';
        return null;
      }

      // [REF: ROLE_ROUTE_BRANCH]
      // Role first, before every gate below it. Two of those gates are wrong
      // for anyone who is not an inspector:
      //
      //  * requiresMfaEnrollment forces TOTP enrollment with no way around it.
      //    An establishment owner is not going to install an authenticator app
      //    to read their sanitary order, and RLS does not need them to:
      //    mfa_satisfied() passes a factor-less account at AAL1.
      //  * /sync runs OfflineService.syncData(), which downloads the
      //    establishment and checklist caches. An owner's RLS returns nothing
      //    from those tables, and the Hive boxes are device-global, so running
      //    it under an owner session used to empty the cache of whichever
      //    inspector shares the phone. (Guarded at the source now too — see
      //    [REF: EMPTY_SNAPSHOT_GUARD] — but an owner has no use for a sync
      //    either way.)
      //
      // An unresolved role is pinned to /sync rather than guessed. Guessing
      // "inspector" marches an owner into MFA enrollment; guessing "owner"
      // hides an inspector's own work from them. The splash resolves the role
      // before it does anything else and then routes.
      if (authProvider.roleUnknown) {
        // RLS hides the profiles row until AAL2, so on a fresh install the
        // role cannot resolve before the code is presented. Waiting on /sync
        // here would never end.
        if (authProvider.mfaChallengePending) {
          return isGoingToMfaVerify ? null : '/mfa-verify';
        }
        return loc == '/sync' ? null : '/sync';
      }

      // A new account nobody has activated. Every policy denies 'pending', so
      // there is no screen in the app with anything on it for this session —
      // see PendingApprovalScreen for why it gets told so explicitly.
      if (authProvider.isPendingApproval) {
        return isGoingToPending ? null : '/pending-approval';
      }
      if (isGoingToPending) return '/sync';

      // Owners: read-only, no sync, no MFA enrollment, nothing under the
      // inspector shell. Checked before the MFA gates, which is the point.
      if (authProvider.isOwner) {
        // [REF: OWNER_SET_PASSWORD]
        // The mailed code is the first sign-in only; nothing else opens until
        // the account has a password.
        if (authProvider.ownerNeedsPassword) {
          return loc == '/my/set-password' ? null : '/my/set-password';
        }
        if (loc == '/my/set-password') return '/my/inspections';
        // /inspection/details/:id is shared with inspectors; RLS decides what
        // a given session can actually read, so there is nothing to duplicate.
        if (isGoingToOwner || loc.startsWith('/inspection/details/')) {
          return null;
        }
        return '/my/inspections';
      }
      // A non-owner who somehow landed on an owner route.
      if (isGoingToOwner) return '/sync';

      // Signed in at AAL1 with a TOTP factor enrolled: the second factor is
      // still owed. Pin to /mfa-verify — data access is blocked server-side
      // by the restrictive AAL2 RLS policies until the code is presented,
      // so there is nothing useful anywhere else anyway.
      if (authProvider.mfaChallengePending) {
        return isGoingToMfaVerify ? null : '/mfa-verify';
      }

      // Authenticated at full assurance but sitting on /login or
      // /mfa-verify: leave.
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
        path: '/pending-approval',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      // Outside the StatefulShellRoute on purpose: the inspector shell
      // (Home / Establishments / History / Profile, Map on the centre button)
      // has nothing an
      // owner is allowed to open, so they get a single screen rather than a
      // shell with three dead branches.
      GoRoute(
        path: '/my/inspections',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OwnerHomeScreen(),
      ),
      GoRoute(
        path: '/my/set-password',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SetPasswordScreen(),
      ),
      // No /establishments/add or /establishments/edit route: the web admin is
      // the sole owner of establishment data, so there is nowhere on mobile to
      // navigate for a create or an edit.
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
          // Index 4: not a bar slot, reached from the centre button.
          StatefulShellBranch(
            navigatorKey: _shellNavigatorMapKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
