import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/insights_service.dart';
import 'insights_dashboard_screen.dart';
import 'multi_block_timer_screen.dart';
import 'study_timer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _bg = Color(0xFF0F1218);
  static const Color _primaryBlue = Color(0xFF4F7CFF);
  static const Color _cardMain = Color(0xFF1A1F2B);
  static const Color _cardElevated = Color(0xFF202636);
  static const Color _cardBlueTint = Color(0xFF1C2A4A);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFF9CA3AF);

  final AuthService _authService = AuthService();
  final InsightsService _insightsService = InsightsService();
  late final Future<_HomeStats> _homeStatsFuture = _loadHomeStats();
  Stream<SessionFlowState>? _sessionFlowStream;

  @override
  void initState() {
    super.initState();
    final user = _authService.currentUser;
    if (user != null) {
      _sessionFlowStream = _insightsService.watchSessionFlowState(
        user.uid,
        recentLimit: 3,
      );
    }
  }

  Future<_HomeStats> _loadHomeStats() async {
    final user = _authService.currentUser;
    if (user == null) {
      return const _HomeStats.empty();
    }

    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final nextDay = dayStart.add(const Duration(days: 1));

      final sessions = await _insightsService.fetchRecentSessions(
        userId: user.uid,
        limit: 60,
      );
      final flow = await _insightsService.fetchSessionFlowState(
        user.uid,
        recentLimit: 3,
      );

      final weeklyMinutes = _buildWeeklyMinutes(sessions);

      int todayStudySeconds = 0;
      int focusCount = 0;
      double focusTotal = 0;

      for (final session in sessions) {
        final ts = session.timestamp;
        if (ts == null) continue;

        if (!ts.isBefore(dayStart) && ts.isBefore(nextDay)) {
          todayStudySeconds += session.durationSeconds;
          if (session.focusScore > 0) {
            focusCount += 1;
            focusTotal += session.focusScore;
          }
        }
      }

      final averageFocusPercent = focusCount == 0
          ? null
          : (focusTotal / focusCount).clamp(0, 100).toDouble();

      return _HomeStats(
        todayStudySeconds: todayStudySeconds,
        averageFocusPercent: averageFocusPercent,
        currentStreakDays: _calculateCurrentStreak(
          sessions.map((e) => e.timestamp),
        ),
        recentSessions: sessions.take(3).toList(),
        weeklyFocusMinutes: weeklyMinutes,
        isWeeklyImproving: _isWeeklyImproving(weeklyMinutes),
        upcomingSession: flow.upcoming,
        currentSession: flow.current,
      );
    } catch (_) {
      return const _HomeStats.empty();
    }
  }

  List<int> _buildWeeklyMinutes(List<FocusSessionRecord> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 6));

    final dayTotals = <DateTime, int>{};
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      dayTotals[day] = 0;
    }

    for (final session in sessions) {
      final ts = session.timestamp;
      if (ts == null) continue;

      final key = DateTime(ts.year, ts.month, ts.day);
      if (dayTotals.containsKey(key)) {
        dayTotals[key] =
            (dayTotals[key] ?? 0) + (session.durationSeconds ~/ 60);
      }
    }

    return dayTotals.entries.map((e) => e.value).toList();
  }

  bool _isWeeklyImproving(List<int> values) {
    if (values.length < 7) return false;

    final firstHalfAvg = (values[0] + values[1] + values[2]) / 3;
    final secondHalfAvg = (values[4] + values[5] + values[6]) / 3;
    return secondHalfAvg >= firstHalfAvg;
  }

  int _calculateCurrentStreak(Iterable<DateTime?> timestamps) {
    final days = <DateTime>{};
    for (final ts in timestamps) {
      if (ts == null) continue;
      days.add(DateTime(ts.year, ts.month, ts.day));
    }

    if (days.isEmpty) return 0;

    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);

    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }

    var streak = 0;
    while (days.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  String _formatStudyTime(int totalSeconds) {
    final totalMinutes = (totalSeconds / 60).floor();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatSessionDuration(int totalSeconds) {
    final minutes = (totalSeconds / 60).round();
    return '$minutes min';
  }

  Future<void> _openPrimarySession({
    SessionPreview? current,
    SessionPreview? upcoming,
  }) async {
    final contextRef = context;
    final user = _authService.currentUser;
    if (user == null) {
      if (!mounted) {
        return;
      }
      Navigator.of(
        contextRef,
      ).push(MaterialPageRoute(builder: (_) => const StudyTimerScreen()));
      return;
    }

    TrackedStudyPlan? plan;
    final planIdCandidate = current?.planId ?? upcoming?.planId;

    if (planIdCandidate != null && planIdCandidate.isNotEmpty) {
      plan = await _insightsService.fetchPlanById(planIdCandidate);
    }

    plan ??= await _insightsService.fetchLatestPlan(user.uid);

    if (!mounted) {
      return;
    }

    if (plan != null && plan.blocks.isNotEmpty) {
      Navigator.of(contextRef).push(
        MaterialPageRoute(
          builder: (_) =>
              MultiBlockTimerScreen(plan: plan!, autostartBlocks: true),
        ),
      );
      return;
    }

    Navigator.of(
      contextRef,
    ).push(MaterialPageRoute(builder: (_) => const StudyTimerScreen()));
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final displayName = user?.displayName?.trim();
    final fallbackName = user?.email?.split('@').first ?? 'there';
    final shortName = (displayName != null && displayName.isNotEmpty)
        ? displayName.split(' ').first
        : fallbackName;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FutureBuilder<_HomeStats>(
          future: _homeStatsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data ?? const _HomeStats.empty();
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final focusLabel = isLoading
                ? '...'
                : (stats.averageFocusPercent == null
                      ? '--'
                      : '${stats.averageFocusPercent!.round()}%');

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const SizedBox(height: 60),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Welcome back, $shortName',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _handleLogout,
                      tooltip: 'Log out',
                      icon: const Icon(Icons.logout_rounded),
                      color: _textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'Let\'s stay consistent today',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                _HomeCard(
                  backgroundColor: _cardBlueTint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Streak',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: _textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isLoading ? '...' : '${stats.currentStreakDays} days',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                StreamBuilder<SessionFlowState>(
                  stream: _sessionFlowStream,
                  initialData: SessionFlowState(
                    current: stats.currentSession,
                    upcoming: stats.upcomingSession,
                    recent: const <FocusSessionRecord>[],
                  ),
                  builder: (context, flowSnapshot) {
                    final flow = flowSnapshot.data;
                    return _PrimarySessionCard(
                      currentSession: flow?.current,
                      upcomingSession: flow?.upcoming,
                      onStartTap: () => _openPrimarySession(
                        current: flow?.current,
                        upcoming: flow?.upcoming,
                      ),
                      onPlanTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const InsightsDashboardScreen(),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _HomeCard(
                        backgroundColor: _cardMain,
                        minHeight: 108,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 14,
                                    color: _textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              isLoading
                                  ? '...'
                                  : _formatStudyTime(stats.todayStudySeconds),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HomeCard(
                        backgroundColor: _cardMain,
                        minHeight: 108,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Focus Score',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 14,
                                    color: _textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              focusLabel,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _HomeCard(
                  backgroundColor: _cardMain,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Focus',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 86,
                        child: _MiniLineChart(
                          values: stats.weeklyFocusMinutes,
                          lineColor: _primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isLoading
                            ? 'Loading weekly trend...'
                            : (stats.isWeeklyImproving
                                  ? 'Focus improving this week'
                                  : 'Keep consistency to improve focus'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _HomeCard(
                  backgroundColor: _cardMain,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Sessions',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (isLoading)
                        Text(
                          'Loading...',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _textSecondary),
                        )
                      else if (stats.recentSessions.isEmpty)
                        Text(
                          'No recent sessions yet',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _textSecondary),
                        )
                      else
                        ...stats.recentSessions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final session = entry.value;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == stats.recentSessions.length - 1
                                  ? 0
                                  : 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    session.subject ?? 'Smart Session',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w500,
                                          color: _textPrimary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatSessionDuration(
                                    session.durationSeconds,
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontSize: 13,
                                        color: _textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const InsightsDashboardScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'View All',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _primaryBlue,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PrimarySessionCard extends StatelessWidget {
  const _PrimarySessionCard({
    required this.onStartTap,
    required this.onPlanTap,
    required this.currentSession,
    required this.upcomingSession,
  });

  final VoidCallback onStartTap;
  final VoidCallback onPlanTap;
  final SessionPreview? currentSession;
  final SessionPreview? upcomingSession;

  @override
  Widget build(BuildContext context) {
    final hasCurrent = currentSession != null;
    final hasUpcoming = upcomingSession != null;

    final startLabel = hasCurrent
        ? 'Continue Plan'
        : hasUpcoming
        ? 'Start Session'
        : 'Start Session';

    final subtitle = hasCurrent
        ? '${currentSession!.subject} in progress'
        : hasUpcoming
        ? 'Next up: ${upcomingSession!.durationMinutes} min'
        : 'Your plan will be organized automatically';

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: _HomeScreenState._primaryBlue,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                startLabel,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onStartTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _HomeScreenState._primaryBlue,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(startLabel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onPlanTap,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Colors.white,
                          width: 1.2,
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Plan Session'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniLineChart extends StatelessWidget {
  const _MiniLineChart({required this.values, required this.lineColor});

  final List<int> values;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final safeValues = values.length == 7 ? values : List<int>.filled(7, 0);

    return CustomPaint(
      painter: _MiniLineChartPainter(values: safeValues, lineColor: lineColor),
      child: const SizedBox.expand(),
    );
  }
}

class _MiniLineChartPainter extends CustomPainter {
  _MiniLineChartPainter({required this.values, required this.lineColor});

  final List<int> values;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1 : maxValue;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final path = Path();
    final dxStep = size.width / (values.length - 1);

    for (var i = 0; i < values.length; i++) {
      final x = i * dxStep;
      final normalized = values[i] / safeMax;
      final y = size.height - (normalized * (size.height - 10)) - 5;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 2.0, pointPaint);
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniLineChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.lineColor != lineColor;
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.child,
    this.minHeight,
    this.backgroundColor,
    this.shadow,
  });

  final Widget child;
  final double? minHeight;
  final Color? backgroundColor;
  final BoxShadow? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: minHeight == null
          ? null
          : BoxConstraints(minHeight: minHeight!),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor ?? _HomeScreenState._cardElevated,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class _HomeStats {
  const _HomeStats({
    required this.todayStudySeconds,
    required this.averageFocusPercent,
    required this.currentStreakDays,
    required this.recentSessions,
    required this.weeklyFocusMinutes,
    required this.isWeeklyImproving,
    required this.upcomingSession,
    required this.currentSession,
  });

  const _HomeStats.empty()
    : todayStudySeconds = 0,
      averageFocusPercent = null,
      currentStreakDays = 0,
      recentSessions = const [],
      weeklyFocusMinutes = const [0, 0, 0, 0, 0, 0, 0],
      isWeeklyImproving = false,
      upcomingSession = null,
      currentSession = null;

  final int todayStudySeconds;
  final double? averageFocusPercent;
  final int currentStreakDays;
  final List<FocusSessionRecord> recentSessions;
  final List<int> weeklyFocusMinutes;
  final bool isWeeklyImproving;
  final SessionPreview? upcomingSession;
  final SessionPreview? currentSession;
}
