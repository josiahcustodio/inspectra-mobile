/// The password rules for new passwords, in one place so the screen that
/// lists them and the check that enforces them cannot disagree. Mirrors the
/// Supabase Auth password policy (min length + lower, upper, digit, symbol),
/// which is what actually refuses a weak one.
library;

class PasswordRules {
  PasswordRules._();

  // The symbol set is Supabase's own; a character outside it would pass here
  // and be refused by the server.
  static final List<(String, RegExp)> rules = [
    ('At least 8 characters', RegExp(r'.{8,}')),
    ('An uppercase letter', RegExp(r'[A-Z]')),
    ('A lowercase letter', RegExp(r'[a-z]')),
    ('A number', RegExp(r'[0-9]')),
    ('A symbol (such as ! @ # ?)', RegExp(r'''[!@#$%^&*()_+\-=\[\]{};':"|<>?,./`~\\]''')),
  ];

  /// How many rules [password] meets, 0 to [rules].length.
  static int level(String password) =>
      rules.where((r) => r.$2.hasMatch(password)).length;

  /// The first unmet rule as a message, or null when the password is acceptable.
  static String? blocker(String password) {
    for (final (label, pattern) in rules) {
      if (!pattern.hasMatch(password)) return 'Password needs: ${label.toLowerCase()}';
    }
    return null;
  }
}
