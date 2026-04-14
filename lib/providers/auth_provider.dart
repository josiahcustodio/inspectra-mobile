import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  User? get user => AuthService.currentUser;
  bool get isAuthenticated => user != null;

  AuthProvider() {
    _init();
  }

  void _init() {
    // Listen to Supabase auth changes
    AuthService.authStateChanges.listen((data) {
      final session = data.session;
      final event = data.event;
      debugPrint('Supabase Auth Event: $event');
      if (session != null) {
        debugPrint('Session persisting! User ID: ${session.user.id}');
      } else {
        debugPrint('No active session.');
      }
      notifyListeners();
    });
  }

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _setErrorMessage(null);

    try {
      await AuthService.signInWithGoogle();
      _setLoading(false);
      return true;
    } catch (e) {
      _setErrorMessage(e.toString());
      _setLoading(false);
      return false;
    }
  }

  Future<void> signOut() async {
    _setLoading(true);
    try {
      await AuthService.signOut();
    } catch (e) {
      _setErrorMessage(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setErrorMessage(String? message) {
    _errorMessage = message;
    notifyListeners();
  }
}
