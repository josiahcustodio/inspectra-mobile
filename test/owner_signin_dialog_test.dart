// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:clowtec_inspector/core/router/app_router.dart';
import 'package:clowtec_inspector/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the auth server answers the code request with, per test.
late http.Response otpResponse;

/// Requests that reached the code endpoint, per test.
int otpRequests = 0;

http.Response okResponse() => http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    );

/// Lets the resend countdown run out, so no timer outlives the test.
Future<void> finishCooldown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 61));
  await tester.pump();
}

Future<void> settleRequest(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
}

Future<void> enterInDialog(WidgetTester tester, String text) => tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      text,
    );

Future<void> openDialogAndSendCode(WidgetTester tester) async {
  final auth = AuthProvider();
  addTearDown(auth.dispose);
  // Built the way main.dart builds it, because the router's refreshListenable
  // is part of what this dialog has to survive.
  final router = createAppRouter(auth);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  final entry = find.text('I own or manage an establishment');
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();

  await enterInDialog(tester, 'owner@example.com');
  await tester.tap(find.text('Send Code'));
  await settleRequest(tester);
}

http.Response errorResponse(int status, String code) => http.Response(
      jsonEncode({'code': status, 'error_code': code, 'msg': code}),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/otp')) otpRequests++;
        return otpResponse;
      }),
    );
  });

  setUp(() => otpRequests = 0);

  testWidgets('a sent code advances the dialog to the code field',
      (tester) async {
    otpResponse = okResponse();
    await openDialogAndSendCode(tester);

    expect(find.text('Enter your code'), findsOneWidget);
    expect(find.text('6-digit code'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Sign In'),
      ),
      findsOneWidget,
    );
    await finishCooldown(tester);
  });

  testWidgets('resend waits out the cooldown, then requests a new code',
      (tester) async {
    otpResponse = okResponse();
    await openDialogAndSendCode(tester);
    expect(otpRequests, 1);
    expect(find.text('Resend code in 60s'), findsOneWidget);

    // Refused during the window the server would only reject.
    await tester.tap(find.text('Resend code in 60s'), warnIfMissed: false);
    await settleRequest(tester);
    expect(otpRequests, 1);

    await finishCooldown(tester);
    await enterInDialog(tester, '123456');
    await tester.tap(find.text('Resend code'));
    await settleRequest(tester);

    expect(otpRequests, 2);
    expect(find.text('Resend code in 60s'), findsOneWidget);
    expect(find.text('123456'), findsNothing, reason: 'the old code is void');
    await finishCooldown(tester);
  });

  testWidgets('a refused resend stays on the code step and says so',
      (tester) async {
    otpResponse = okResponse();
    await openDialogAndSendCode(tester);
    await finishCooldown(tester);

    otpResponse = errorResponse(429, 'over_email_send_rate_limit');
    await tester.tap(find.text('Resend code'));
    await settleRequest(tester);

    expect(find.text('6-digit code'), findsOneWidget);
    expect(find.textContaining('Too many attempts'), findsOneWidget);
  });

  testWidgets('a wrong or expired code says so and offers a new one',
      (tester) async {
    otpResponse = okResponse();
    await openDialogAndSendCode(tester);

    otpResponse = errorResponse(403, 'otp_expired');
    await enterInDialog(tester, '000000');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Sign In'),
      ),
    );
    await settleRequest(tester);

    expect(find.textContaining('wrong or has expired'), findsOneWidget);
    await finishCooldown(tester);
  });

  testWidgets('an unknown address advances too, so it reveals nothing',
      (tester) async {
    otpResponse = errorResponse(422, 'otp_disabled');
    await openDialogAndSendCode(tester);

    expect(find.text('6-digit code'), findsOneWidget);
    await finishCooldown(tester);
  });

  testWidgets('a rate limit stays on the email step and says so',
      (tester) async {
    otpResponse = errorResponse(429, 'over_email_send_rate_limit');
    await openDialogAndSendCode(tester);

    expect(find.text('6-digit code'), findsNothing);
    expect(find.textContaining('Too many attempts'), findsOneWidget);
  });
}
