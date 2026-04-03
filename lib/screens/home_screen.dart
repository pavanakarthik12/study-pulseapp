import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'insights_dashboard_screen.dart';
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
  late final Future<_HomeStats> _homeStatsFuture = _loadHomeStats();

  Future<_HomeStats> _loadHomeStats() async {
    final user = _authService.currentUser;
    if (user == null) {
      return const _HomeStats.empty();
    }

    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final nextDay = dayStart.add(const Duration(days: 1));

      final querySnapshot = await FirebaseFirestore.instance
          .collection('focus_sessions')
          .where('user_id', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(60)
          .get();

      final sessions = querySnapshot.docs
          .map((doc) => _SessionSample.fromMap(doc.data()))
          .whereType<_SessionSample>()
          .toList();

      final weeklyMinutes = _buildWeeklyMinutes(sessions);

      int todayStudySeconds = 0;
      int focusCount = 0;
      double focusTotal = 0;

      for (final session in sessions) {
        final ts = session.startedAt;
        if (ts == null) continue;

        if (!ts.isBefore(dayStart) && ts.isBefore(nextDay)) {
          todayStudySeconds += session.durationSeconds;
          if (session.focusScore != null) {
            focusCount += 1;
            focusTotal += session.focusScore!;
          }
        }
      }

      final averageFocusPercent =
          focusCount == 0 ? null : (focusTotal / focusCount).clamp(0, 100).toDouble();

      return _HomeStats(
        todayStudySeconds: todayStudySeconds,
        averageFocusPercent: averageFocusPercent,
        currentStreakDays: _calculateCurrentStreak(sessions.map((e) => e.startedAt)),
        recentSessions: sessions.take(3).toList(),
        weeklyFocusMinutes: weeklyMinutes,
        isWeeklyImproving: _isWeeklyImproving(weeklyMinutes),
      );
    } catch (_) {
      return const _HomeStats.empty();
    }
  }

  List<int> _buildWeeklyMinutes(List<_SessionSample> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 6));

    final dayTotals = <DateTime, int>{};
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      dayTotals[day] = 0;
    }

    for (final session in sessions) {
      final ts = session.startedAt;
      if (ts == null) continue;

      final key = DateTime(ts.year, ts.month, ts.day);
      if (dayTotals.containsKey(key)) {
        dayTotals[key] = (dayTotals[key] ?? 0) + (session.durationSeconds ~/ 60);
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
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            final focusLabel = isLoading
                ? '...'
                : (stats.averageFocusPercent == null
                    ? '--'
                    : '${stats.averageFocusPercent!.round()}%');

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const SizedBox(height: 60),
                Text(
                  'Welcome back, $shortName',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
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
                  shadow: const BoxShadow(
                    color: Color(0x1A4F7CFF),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
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
                _PrimarySessionCard(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StudyTimerScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const InsightsDashboardScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: _cardElevated,
                      foregroundColor: _textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Plan Session',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _textSecondary,
                          ),
                    ),
                  ),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 14,
                                    color: _textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              isLoading ? '...' : _formatStudyTime(stats.todayStudySeconds),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 14,
                                    color: _textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              focusLabel,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _textSecondary,
                              ),
                        )
                      else if (stats.recentSessions.isEmpty)
                        Text(
                          'No recent sessions yet',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _textSecondary,
                              ),
                        )
                      else
                        ...stats.recentSessions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final session = entry.value;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == stats.recentSessions.length - 1 ? 0 : 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    session.subject,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w500,
                                          color: _textPrimary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatSessionDuration(session.durationSeconds),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
  const _PrimarySessionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: _HomeScreenState._primaryBlue,
            boxShadow: const [
              BoxShadow(
                color: Color(0x224F7CFF),
                blurRadius: 20,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start Smart Session',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your plan will be organized automatically',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniLineChart extends StatelessWidget {
  const _MiniLineChart({
    required this.values,
    required this.lineColor,
  });

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
      constraints: minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor ?? _HomeScreenState._cardElevated,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          shadow ??
              const BoxShadow(
                color: Color(0x16000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
        ],
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
  });

  const _HomeStats.empty()
      : todayStudySeconds = 0,
        averageFocusPercent = null,
        currentStreakDays = 0,
        recentSessions = const [],
        weeklyFocusMinutes = const [0, 0, 0, 0, 0, 0, 0],
        isWeeklyImproving = false;

  final int todayStudySeconds;
  final double? averageFocusPercent;
  final int currentStreakDays;
  final List<_SessionSample> recentSessions;
  final List<int> weeklyFocusMinutes;
  final bool isWeeklyImproving;
}

class _SessionSample {
  const _SessionSample({
    required this.startedAt,
    required this.durationSeconds,
    required this.focusScore,
    required this.subject,
  });

  final DateTime? startedAt;
  final int durationSeconds;
  final double? focusScore;
  final String subject;

  static _SessionSample? fromMap(Map<String, dynamic> data) {
    DateTime? timestamp;
    final rawTimestamp = data['timestamp'] ?? data['session_started_at'];
    if (rawTimestamp is Timestamp) {
      timestamp = rawTimestamp.toDate();
    }

    final duration = (data['total_duration_seconds'] as num?)?.toInt() ??
        (data['session_duration'] as num?)?.toInt() ??
        (data['duration_seconds'] as num?)?.toInt() ??
        0;

    if (duration <= 0 && timestamp == null) {
      return null;
    }

    final subject = (data['subject'] as String?)?.trim();

    return _SessionSample(
      startedAt: timestamp,
      durationSeconds: duration,
      focusScore: (data['focus_score'] as num?)?.toDouble(),
      subject: (subject == null || subject.isEmpty) ? 'Smart Session' : subject,
    );
  }
}
