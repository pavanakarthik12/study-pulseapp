import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import 'focus_history_screen.dart';
import 'insights_dashboard_screen.dart';
import 'study_timer_screen.dart';
import 'widgets/modern_components.dart';

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
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.lg),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppTheme.xs),
                        Text(
                          userLabel,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: authService.signOut,
                      icon: const Icon(Icons.logout_rounded),
                      tooltip: 'Logout',
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.bgCard,
                        foregroundColor: AppTheme.accentSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  children: [
                    PrimaryButton(
                      label: 'Start Smart Session',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StudyTimerScreen(),
                          ),
                        );
                      },
                      fullWidth: true,
                    )
                        .animate(delay: 100.ms)
                        .fade(duration: 450.ms)
                        .slideY(begin: 0.1, end: 0, duration: 450.ms),
                    const SizedBox(height: AppTheme.md),
                    SecondaryButton(
                      label: 'View Insights Dashboard',
                      icon: Icons.insights_rounded,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const InsightsDashboardScreen(),
                          ),
                        );
                      },
                      fullWidth: true,
                    )
                        .animate(delay: 150.ms)
                        .fade(duration: 450.ms)
                        .slideY(begin: 0.1, end: 0, duration: 450.ms),
                    const SizedBox(height: AppTheme.md),
                    SecondaryButton(
                      label: 'Focus History',
                      icon: Icons.analytics_outlined,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FocusHistoryScreen(),
                          ),
                        );
                      },
                      fullWidth: true,
                    )
                        .animate(delay: 200.ms)
                        .fade(duration: 450.ms)
                        .slideY(begin: 0.1, end: 0, duration: 450.ms),
                  ],
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}