import 'package:clowtec_inspector/core/password_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a password meeting every rule passes', () {
    expect(PasswordRules.blocker('Lomi-House1'), isNull);
    expect(PasswordRules.level('Lomi-House1'), PasswordRules.rules.length);
  });

  test('each missing rule is named', () {
    expect(PasswordRules.blocker('Ab1!'), contains('8 characters'));
    expect(PasswordRules.blocker('lomi-house1'), contains('uppercase'));
    expect(PasswordRules.blocker('LOMI-HOUSE1'), contains('lowercase'));
    expect(PasswordRules.blocker('Lomi-House'), contains('number'));
    expect(PasswordRules.blocker('LomiHouse1'), contains('symbol'));
  });

  test('a space is not a symbol, matching the server policy', () {
    expect(PasswordRules.blocker('Lomi House1'), contains('symbol'));
  });
}
