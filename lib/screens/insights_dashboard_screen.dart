import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/theme.dart';
import '../services/insights_service.dart';
import 'multi_block_timer_screen.dart';
import 'widgets/modern_components.dart';

class InsightsDashboardScreen extends StatefulWidget {
  const InsightsDashboardScreen({super.key});

  @override
  State<InsightsDashboardScreen> createState() => _InsightsDashboardScreenState();
}

class _InsightsDashboardScreenState extends State<InsightsDashboardScreen> {
  final InsightsService _insightsService = InsightsService();
  final TextEditingController _subjectsController = TextEditingController();

  late Future<_DashboardData> _insightsFuture;

  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  List<TrackedPlanBlock> _trackedBlocks = const <TrackedPlanBlock>[];
  String? _activePlanId;
  bool _isCreatingPlan = false;
  final Set<int> _updatingBlockIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    _insightsFuture = _loadInsights();
  }

  @override
  void dispose() {
    _subjectsController.dispose();
    super.dispose();
  }

  Future<_DashboardData> _loadInsights() async {
    try {
      final sessions = await _insightsService.fetchRecentSessions();
      final userId = FirebaseAuth.instance.currentUser?.uid;

      final summary = _insightsService.buildInsightsSummary(sessions);
      final trend = _insightsService.buildRecentDailyTrend(sessions);

      final streak = _insightsService.calculateStreakFromSessions(sessions);
      final goal = _insightsService.calculateWeeklyGoal(sessions);

      if (userId != null && userId.isNotEmpty) {
        unawaited(_insightsService.updateStreakData(userId, streak));
      }

      return _DashboardData(
        summary: summary,
        weeklyTrend: trend,
        streak: streak,
        weeklyGoal: goal,
      );
    } catch (_) {
      return _DashboardData(
        summary: const InsightsSummary(
          totalStudySeconds: 0,
          averageFocusScore: 0,
          bestSessionTimeLabel: 'Error loading',
          bestFocusWindowLabel: 'Failed to load data',
          timeOfDayStats: <TimeOfDayStats>[],
          totalSessions: 0,
        ),
        weeklyTrend: const <DailyTrendPoint>[],
        streak: const StreakData(
          currentStreak: 0,
          longestStreak: 0,
          lastSessionDate: null,
          hasSevenDayBadge: false,
          hasThirtyDayBadge: false,
        ),
        weeklyGoal: WeeklyGoal(
          targetSessions: 5,
          currentWeekSessionCount: 0,
          weekStartDate: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _pickStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );

    if (selected != null) {
      setState(() {
        _startTime = selected;
      });
    }
  }

  Future<void> _pickEndTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );

    if (selected != null) {
      setState(() {
        _endTime = selected;
      });
    }
  }

  Future<void> _generatePlan() async {
    final subjects = _subjectsController.text
        .split(RegExp(r'[\n,]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    final blocks = _insightsService.generatePlan(
      subjects: subjects,
      startTime: _startTime,
      endTime: _endTime,
    );

    if (blocks.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activePlanId = null;
        _trackedBlocks = const <TrackedPlanBlock>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Time range is too short. Add at least 25 minutes.'),
        ),
      );
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to save and track plan progress.'),
        ),
      );
      return;
    }

    setState(() {
      _isCreatingPlan = true;
    });

    try {
      final trackedPlan = await _insightsService.createStudyPlan(
        userId: userId,
        blocks: blocks,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _activePlanId = trackedPlan.id;
        _trackedBlocks = trackedPlan.blocks;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save plan to Firestore right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingPlan = false;
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) {
      return '${minutes}m';
    }
    return '${hours}h ${minutes}m';
  }

  Future<void> _updateBlockStatus({
    required int index,
    required PlanBlockStatus status,
  }) async {
    final planId = _activePlanId;
    if (planId == null || index < 0 || index >= _trackedBlocks.length) {
      return;
    }

    if (_updatingBlockIndexes.contains(index)) {
      return;
    }

    final previous = List<TrackedPlanBlock>.from(_trackedBlocks);
    final optimistic = List<TrackedPlanBlock>.from(_trackedBlocks);
    optimistic[index] = optimistic[index].copyWith(status: status);

    setState(() {
      _updatingBlockIndexes.add(index);
      _trackedBlocks = optimistic;
    });

    try {
      await _insightsService.updateBlockStatus(
        planId: planId,
        blockIndex: index,
        status: status,
        blocks: previous,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _trackedBlocks = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status update failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingBlockIndexes.remove(index);
        });
      }
    }
  }

  void _startStudySession() {
    if (_activePlanId == null || _trackedBlocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No study plan generated yet.')),
      );
      return;
    }

    final plan = TrackedStudyPlan(
      id: _activePlanId!,
      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      blocks: _trackedBlocks,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiBlockTimerScreen(
          plan: plan,
          autostartBlocks: false,
        ),
      ),
    );
  }

  Color _statusColor(PlanBlockStatus status) {
    switch (status) {
      case PlanBlockStatus.done:
        return const Color(0xFF4BD37B);
      case PlanBlockStatus.skipped:
        return const Color(0xFFFF6B6B);
      case PlanBlockStatus.pending:
        return Colors.white.withValues(alpha: 0.45);
    }
  }

  String _statusLabel(PlanBlockStatus status) {
    switch (status) {
      case PlanBlockStatus.done:
        return 'Done';
      case PlanBlockStatus.skipped:
        return 'Skipped';
      case PlanBlockStatus.pending:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              _insightsFuture = _loadInsights();
              await _insightsFuture;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppTheme.lg, AppTheme.lg, AppTheme.lg, 36),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Insights Dashboard',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Data-driven focus analytics with an auto-generated planner. Pull down to refresh.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.74),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Your Insights',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<_DashboardData>(
                  future: _insightsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const GlassCard(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return GlassCard(
                        child: Text(
                          'Could not load insights right now.',
                          style: theme.textTheme.bodyLarge,
                        ),
                      );
                    }

                    final payload = snapshot.data ??
                        _DashboardData(
                          summary: const InsightsSummary(
                            totalStudySeconds: 0,
                            averageFocusScore: 0,
                            bestSessionTimeLabel: 'No sessions yet',
                            bestFocusWindowLabel: 'Not enough data yet',
                            timeOfDayStats: <TimeOfDayStats>[],
                            totalSessions: 0,
                          ),
                          weeklyTrend: const <DailyTrendPoint>[],
                          streak: const StreakData(
                            currentStreak: 0,
                            longestStreak: 0,
                            lastSessionDate: null,
                            hasSevenDayBadge: false,
                            hasThirtyDayBadge: false,
                          ),
                          weeklyGoal: WeeklyGoal(
                            targetSessions: 5,
                            currentWeekSessionCount: 0,
                            weekStartDate: DateTime.now(),
                          ),
                        );

                    final summary = payload.summary;
                    final streak = payload.streak;
                    final goal = payload.weeklyGoal;

                    return Column(
                      children: [
                        GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '🔥 ${streak.currentStreak}-Day Streak',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Longest: ${streak.longestStreak} days',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      if (streak.hasSevenDayBadge)
                                        Tooltip(
                                          message: '7-Day Streak Badge',
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: const Color(0xFFFFD700)
                                                  .withValues(alpha: 0.2),
                                            ),
                                            child: const Text(
                                              '⭐',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      if (streak.hasThirtyDayBadge)
                                        Tooltip(
                                          message: '30-Day Streak Badge',
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: const Color(0xFF4BD37B)
                                                  .withValues(alpha: 0.2),
                                            ),
                                            child: const Text(
                                              '👑',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Weekly Goal',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${goal.currentWeekSessionCount}/${goal.targetSessions}',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: goal.isCompleted
                                                ? const Color(0xFF4BD37B)
                                                : const Color(0xFF57D2FF),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: (goal.currentWeekSessionCount /
                                                goal.targetSessions)
                                            .clamp(0.0, 1.0),
                                        minHeight: 6,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.15),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          goal.isCompleted
                                              ? const Color(0xFF4BD37B)
                                              : const Color(0xFF57D2FF),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _MetricCard(
                                    title: 'Total Study Time',
                                    value: _formatDuration(summary.totalStudySeconds),
                                    icon: Icons.timer_outlined,
                                  ),
                                  _MetricCard(
                                    title: 'Average Focus Score',
                                    value: '${summary.averageFocusScore.toStringAsFixed(1)}%',
                                    icon: Icons.psychology_alt_outlined,
                                  ),
                                  _MetricCard(
                                    title: 'Best Study Time',
                                    value: summary.bestSessionTimeLabel,
                                    icon: Icons.schedule,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                summary.bestFocusWindowLabel,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (summary.timeOfDayStats.isEmpty)
                                Text(
                                  'Complete more sessions to unlock time-of-day grouping insights.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              if (summary.timeOfDayStats.isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: summary.timeOfDayStats
                                      .map(
                                        (segment) => Chip(
                                          label: Text(
                                            '${segment.label}: ${segment.averageFocusScore.toStringAsFixed(0)}% (${segment.sessionCount})',
                                          ),
                                          backgroundColor:
                                              Colors.white.withValues(alpha: 0.08),
                                          side: BorderSide(
                                            color: Colors.white.withValues(alpha: 0.2),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weekly Trends (7 days)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Study time and focus score trends from recent sessions.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.68),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _TrendBarStrip(
                                title: 'Daily Study Time',
                                points: payload.weeklyTrend,
                                valueGetter: (point) => point.totalStudySeconds / 3600,
                                valueLabelBuilder: (point) {
                                  final mins = (point.totalStudySeconds / 60).round();
                                  return '${mins}m';
                                },
                              ),
                              const SizedBox(height: 16),
                              _TrendBarStrip(
                                title: 'Daily Average Focus',
                                points: payload.weeklyTrend,
                                valueGetter: (point) => point.averageFocusScore,
                                valueLabelBuilder: (point) =>
                                    '${point.averageFocusScore.toStringAsFixed(0)}%',
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  "Today's Plan",
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _subjectsController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Add subjects/tasks (comma or new line separated)',
                          prefixIcon: Icon(Icons.checklist_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickStartTime,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text('Start: ${_startTime.format(context)}'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickEndTime,
                              icon: const Icon(Icons.flag_rounded),
                              label: Text('End: ${_endTime.format(context)}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.md),
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          label: 'Generate Auto Plan',
                          isLoading: _isCreatingPlan,
                          onPressed: _generatePlan,
                          fullWidth: true,
                        ),
                      ),
                      const SizedBox(height: AppTheme.md),
                      Text(
                        'Auto plan rules: 25-45 min study blocks, 5-10 min breaks, tasks assigned sequentially.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_activePlanId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Plan is synced to Firestore. Mark blocks as done or skipped to track behavior.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.74),
                      ),
                    ),
                  ),
                if (_trackedBlocks.isEmpty)
                  Text(
                    'No generated sessions yet. Add tasks and time range, then tap Generate Auto Plan.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                if (_trackedBlocks.isNotEmpty)
                  ..._trackedBlocks.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TrackedPlanBlockTile(
                        block: entry.value,
                        statusColor: _statusColor(entry.value.status),
                        statusLabel: _statusLabel(entry.value.status),
                        isUpdating: _updatingBlockIndexes.contains(entry.key),
                        onDone: entry.value.status == PlanBlockStatus.pending
                            ? () => _updateBlockStatus(
                                  index: entry.key,
                                  status: PlanBlockStatus.done,
                                )
                            : null,
                        onSkip: entry.value.status == PlanBlockStatus.pending
                            ? () => _updateBlockStatus(
                                  index: entry.key,
                                  status: PlanBlockStatus.skipped,
                                )
                            : null,
                      ),
                    ),
                  ),
                if (_trackedBlocks.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.lg),
                  PrimaryButton(
                    label: 'Start Study Session',
                    onPressed: _startStudySession,
                    fullWidth: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackedPlanBlockTile extends StatelessWidget {
  const _TrackedPlanBlockTile({
    required this.block,
    required this.statusLabel,
    required this.statusColor,
    required this.onDone,
    required this.onSkip,
    this.isUpdating = false,
  });

  final TrackedPlanBlock block;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback? onDone;
  final VoidCallback? onSkip;
  final bool isUpdating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor.withValues(alpha: 0.85)),
          color: statusColor.withValues(alpha: 0.08),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              block.type == PlanBlockType.study
                  ? Icons.menu_book_rounded
                  : Icons.free_breakfast_rounded,
              color: statusColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          block.subject,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: statusColor.withValues(alpha: 0.2),
                        ),
                        child: Text(
                          statusLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${block.durationMinutes} min',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isUpdating ? null : onDone,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Mark Done'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4BD37B),
                            side: BorderSide(
                              color: const Color(0xFF4BD37B)
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isUpdating ? null : onSkip,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Skip'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6B6B),
                            side: BorderSide(
                              color: const Color(0xFFFF6B6B)
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isUpdating)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Updating status...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.of(context).size.width - 72) / 2;

    return Container(
      constraints: BoxConstraints(minWidth: 120, maxWidth: maxWidth),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                ),
          ),
        ],
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.summary,
    required this.weeklyTrend,
    required this.streak,
    required this.weeklyGoal,
  });

  final InsightsSummary summary;
  final List<DailyTrendPoint> weeklyTrend;
  final StreakData streak;
  final WeeklyGoal weeklyGoal;
}

class _TrendBarStrip extends StatelessWidget {
  const _TrendBarStrip({
    required this.title,
    required this.points,
    required this.valueGetter,
    required this.valueLabelBuilder,
  });

  final String title;
  final List<DailyTrendPoint> points;
  final double Function(DailyTrendPoint point) valueGetter;
  final String Function(DailyTrendPoint point) valueLabelBuilder;

  String _dayShortLabel(DateTime day) {
    const names = <int, String>{
      DateTime.monday: 'M',
      DateTime.tuesday: 'T',
      DateTime.wednesday: 'W',
      DateTime.thursday: 'T',
      DateTime.friday: 'F',
      DateTime.saturday: 'S',
      DateTime.sunday: 'S',
    };
    return names[day.weekday] ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = points.isEmpty
        ? 0.0
        : points.map(valueGetter).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: points.map((point) {
            final rawValue = valueGetter(point);
            final normalized = maxValue <= 0 ? 0.0 : (rawValue / maxValue);

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      valueLabelBuilder(point),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 62,
                      width: double.infinity,
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: (normalized.clamp(0.08, 1.0)).toDouble(),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xFF57D2FF), Color(0xFF7C9BFF)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dayShortLabel(point.day),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
