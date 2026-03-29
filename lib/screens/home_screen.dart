import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'focus_history_screen.dart';
import 'study_timer_screen.dart';
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
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StudyTimerScreen(),
                        ),
                      );
                    },
                  ),
                )
                    .animate(delay: 220.ms)
                    .fade(duration: 500.ms)
                    .slideY(begin: 0.08, end: 0, duration: 500.ms),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FocusHistoryScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('View Focus History'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                )
                    .animate(delay: 280.ms)
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