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

  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? name,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      await credential.user?.updateDisplayName(trimmedName);
      await credential.user?.reload();
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }
}