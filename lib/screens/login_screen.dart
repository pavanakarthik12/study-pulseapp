import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import 'widgets/modern_components.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signInWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Login failed')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Study Pulse',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    )
                        .animate()
                        .fade(duration: 450.ms)
                        .slideY(begin: 0.12, end: 0, duration: 450.ms),
                    const SizedBox(height: AppTheme.md),
                    Text(
                      'Train your focus',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                        .animate(delay: 120.ms)
                        .fade(duration: 450.ms)
                        .slideY(begin: 0.12, end: 0, duration: 450.ms),
                    const SizedBox(height: AppTheme.xl),
                    ModernCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            ModernTextField(
                              controller: _emailController,
                              label: 'Email',
                              hint: 'Enter your email',
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icons.mail_outline_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppTheme.lg),
                            ModernTextField(
                              controller: _passwordController,
                              label: 'Password',
                              hint: 'Enter your password',
                              obscureText: true,
                              prefixIcon: Icons.lock_outline_rounded,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Enter your password';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppTheme.xl),
                            PrimaryButton(
                              label: 'Login',
                              isLoading: _isLoading,
                              onPressed: _login,
                              fullWidth: true,
                            ),
                            const SizedBox(height: AppTheme.md),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Don\'t have an account? ',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                TertiaryButton(
                                  label: 'Sign up',
                                  onPressed: _isLoading
                                      ? () {}
                                      : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SignupScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                        .animate(delay: 220.ms)
                        .fade(duration: 500.ms)
                        .slideY(begin: 0.08, end: 0, duration: 500.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}