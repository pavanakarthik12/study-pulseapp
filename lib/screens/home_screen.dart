import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'widgets/ui_shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;
    final userLabel = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : (user?.email ?? 'Unknown user');

    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: authService.signOut,
                      icon: const Icon(Icons.logout),
                      tooltip: 'Logout',
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                )
                    .animate()
                    .fade(duration: 450.ms)
                    .slideY(begin: 0.12, end: 0, duration: 450.ms),
                const SizedBox(height: 10),
                Text(
                  userLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                )
                    .animate(delay: 120.ms)
                    .fade(duration: 450.ms)
                    .slideY(begin: 0.12, end: 0, duration: 450.ms),
                const SizedBox(height: 34),
                SizedBox(
                  width: 280,
                  child: GradientActionButton(
                    label: 'Start Smart Session',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Smart Session started!')),
                      );
                    },
                  ),
                )
                    .animate(delay: 220.ms)
                    .fade(duration: 500.ms)
                    .slideY(begin: 0.08, end: 0, duration: 500.ms),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}