import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  AppUser? get currentUser {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return null;
    }
    return AppUser.fromFirebaseUser(user);
  }

  Future<User?> signUp(String email, String password) async {
    final result = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return result.user;
  }

  Future<User?> login(String email, String password) async {
    final result = await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return result.user;
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
  }

  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await login(email, password);
  }

  Future<void> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? name,
  }) async {
    final user = await signUp(email, password);

    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      await user?.updateDisplayName(trimmedName);
      await user?.reload();
    }
  }

  Future<void> signOut() async {
    await logout();
  }
}