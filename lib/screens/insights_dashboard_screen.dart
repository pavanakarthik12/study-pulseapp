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
  State<InsightsDashboardScreen> createState() =>
      _InsightsDashboardScreenState();
}

class _InsightsDashboardScreenState extends State<InsightsDashboardScreen> {
  static const Color _bg = Color(0xFF0F1218);
  static const Color _card = Color(0xFF1A1F2B);
  static const Color _cardElevated = Color(0xFF202636);
  static const Color _accent = Color(0xFF4F7CFF);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFF9CA3AF);

  final InsightsService _insightsService = InsightsService();
  final TextEditingController _subjectsController = TextEditingController();

  late Future<_DashboardData> _insightsFuture;
  StreamSubscription<String>? _sessionUpdatesSubscription;
  StreamSubscription<TrackedStudyPlan?>? _planSubscription;

  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  List<TrackedPlanBlock> _trackedBlocks = const <TrackedPlanBlock>[];
  String? _activePlanId;
  bool _isCreatingPlan = false;
  final Set<int> _updatingBlockIndexes = <int>{};

  bool _isLocalPlanId(String planId) => planId.startsWith('local_');

  @override
  void initState() {
    super.initState();
    _insightsFuture = _loadInsights();

    _sessionUpdatesSubscription = InsightsService.watchSessionUpdates().listen((
      uid,
    ) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (!mounted || currentUid == null || uid != currentUid) {
        return;
      }

      setState(() {
        _insightsFuture = _loadInsights();
      });
    });

    unawaited(_restoreLatestPlan());
  }

  @override
  void dispose() {
    _sessionUpdatesSubscription?.cancel();
    _planSubscription?.cancel();
    _subjectsController.dispose();
    super.dispose();
  }

  Future<void> _restoreLatestPlan() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return;
    }

    try {
      final latestPlan = await _insightsService.fetchLatestPlan(userId);
      if (!mounted || latestPlan == null || latestPlan.blocks.isEmpty) {
        return;
      }

      setState(() {
        _activePlanId = latestPlan.id;
        _trackedBlocks = latestPlan.blocks;
      });

      _subscribeToPlan(latestPlan.id);
    } catch (_) {
      // Best-effort restore only.
    }
  }

  void _subscribeToPlan(String planId) {
    _planSubscription?.cancel();
    _planSubscription = _insightsService.watchStudyPlan(planId).listen((plan) {
      if (!mounted || plan == null) {
        return;
      }

      setState(() {
        _activePlanId = plan.id;
        _trackedBlocks = plan.blocks;
      });
    });
  }

  Future<_DashboardData> _loadInsights() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null || userId.isEmpty) {
        return _DashboardData(
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
      }

      final sessions = await _insightsService.fetchRecentSessions(
        userId: userId,
      );
      final completedSessions = sessions
          .where((session) => session.completed)
          .toList();

      final summary = _insightsService.buildInsightsSummary(sessions);
      final trend = _insightsService.buildRecentDailyTrend(sessions);

      final streak = _insightsService.calculateStreakFromSessions(
        completedSessions,
      );
      final goal = _insightsService.calculateWeeklyGoal(completedSessions);

      unawaited(_insightsService.updateStreakData(userId, streak));

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

    final localTrackedBlocks = blocks
        .asMap()
        .entries
        .map(
          (entry) => TrackedPlanBlock(
            subject: entry.value.subject ?? 'Short Break',
            durationMinutes: entry.value.durationMinutes,
            status: PlanBlockStatus.pending,
            type: entry.value.type,
            orderIndex: entry.key,
          ),
        )
        .toList();

    final localPlanId = 'local_${DateTime.now().millisecondsSinceEpoch}';

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activePlanId = localPlanId;
        _trackedBlocks = localTrackedBlocks;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Plan generated locally. Login to sync and track progress.',
          ),
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
      _subscribeToPlan(trackedPlan.id);
    } catch (e) {
      debugPrint('Could not sync plan to Firestore: $e');
      if (!mounted) {
        return;
      }
      _planSubscription?.cancel();
      setState(() {
        _activePlanId = localPlanId;
        _trackedBlocks = localTrackedBlocks;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Plan generated locally. Firestore sync is unavailable right now.',
          ),
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

    if (_isLocalPlanId(planId)) {
      setState(() {
        _updatingBlockIndexes.remove(index);
      });
      return;
    }

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
        _activePlanId = 'local_${DateTime.now().millisecondsSinceEpoch}';
        _trackedBlocks = optimistic;
      });
      _planSubscription?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Status saved locally. Cloud sync is unavailable right now.',
          ),
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
        builder: (_) =>
            MultiBlockTimerScreen(plan: plan, autostartBlocks: false),
      ),
    );
  }

  String _statusLabel(PlanBlockStatus status, {bool isNextUpcoming = false}) {
    switch (status) {
      case PlanBlockStatus.active:
        return 'Active';
      case PlanBlockStatus.completed:
        return 'Completed';
      case PlanBlockStatus.skipped:
        return 'Skipped';
      case PlanBlockStatus.pending:
        return isNextUpcoming ? 'Up Next' : 'Upcoming';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _insightsFuture = _loadInsights();
            });
            await _insightsFuture;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: _textPrimary,
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Insights Dashboard',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Data-driven focus analytics with an auto-generated planner. Pull down to refresh.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FutureBuilder<_DashboardData>(
                future: _insightsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _SectionContainer(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return _SectionContainer(
                      child: Text(
                        'Could not load insights right now.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: _textPrimary,
                        ),
                      ),
                    );
                  }

                  final payload =
                      snapshot.data ??
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionContainer(
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
                                      '${streak.currentStreak}-Day Streak',
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimary,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Longest: ${streak.longestStreak} days',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: _textSecondary),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    if (streak.hasSevenDayBadge)
                                      _BadgeChip(label: '7D'),
                                    if (streak.hasSevenDayBadge &&
                                        streak.hasThirtyDayBadge)
                                      const SizedBox(width: 8),
                                    if (streak.hasThirtyDayBadge)
                                      _BadgeChip(label: '30D'),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: _cardElevated,
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
                                              color: _textPrimary,
                                            ),
                                      ),
                                      Text(
                                        '${goal.currentWeekSessionCount}/${goal.targetSessions}',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: goal.isCompleted
                                                  ? const Color(0xFF4BD37B)
                                                  : _accent,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value:
                                          (goal.currentWeekSessionCount /
                                                  goal.targetSessions)
                                              .clamp(0.0, 1.0),
                                      minHeight: 6,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        goal.isCompleted
                                            ? const Color(0xFF4BD37B)
                                            : _accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.38,
                              children: [
                                _MetricCard(
                                  title: 'Total Study Time',
                                  value: _formatDuration(
                                    summary.totalStudySeconds,
                                  ),
                                  icon: Icons.timer_outlined,
                                ),
                                _MetricCard(
                                  title: 'Average Focus Score',
                                  value:
                                      '${summary.averageFocusScore.toStringAsFixed(1)}%',
                                  icon: Icons.psychology_alt_outlined,
                                ),
                                _MetricCard(
                                  title: 'Best Study Time',
                                  value: summary.bestSessionTimeLabel,
                                  icon: Icons.schedule,
                                ),
                                _MetricCard(
                                  title: 'Sessions Completed',
                                  value: '${summary.totalSessions}',
                                  icon: Icons.check_circle_outline_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              summary.bestFocusWindowLabel,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (summary.timeOfDayStats.isEmpty)
                              Text(
                                'Complete more sessions to unlock time-of-day grouping insights.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: _textSecondary,
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
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(color: _textPrimary),
                                        ),
                                        backgroundColor: _cardElevated,
                                        side: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weekly Trends (7 days)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Study time and focus score trends from recent sessions.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _textSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _TrendBarStrip(
                              title: 'Daily Study Time',
                              points: payload.weeklyTrend,
                              valueGetter: (point) =>
                                  point.totalStudySeconds / 3600,
                              valueLabelBuilder: (point) {
                                final mins = (point.totalStudySeconds / 60)
                                    .round();
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
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _SectionContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _subjectsController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText:
                            'Add subjects/tasks (comma or new line separated)',
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
                        color: _textSecondary,
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
                    _isLocalPlanId(_activePlanId!)
                        ? 'Plan is stored locally. Login or restore connectivity to sync to Firestore.'
                        : 'Plan is synced to Firestore. Update blocks to keep your progress accurate.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _textSecondary,
                    ),
                  ),
                ),
              if (_trackedBlocks.isEmpty)
                Text(
                  'No generated sessions yet. Add tasks and time range, then tap Generate Auto Plan.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _textSecondary,
                  ),
                ),
              if (_trackedBlocks.isNotEmpty)
                Builder(
                  builder: (context) {
                    TrackedPlanBlock? current;
                    TrackedPlanBlock? next;

                    for (final block in _trackedBlocks) {
                      if (current == null &&
                          block.status == PlanBlockStatus.active) {
                        current = block;
                      }
                      if (next == null &&
                          block.status == PlanBlockStatus.pending) {
                        next = block;
                      }
                      if (current != null && next != null) {
                        break;
                      }
                    }

                    if (current == null && next == null) {
                      return const SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (current != null)
                              _PlanSummaryRow(
                                title: 'Current Session',
                                subject: current.subject,
                                durationMinutes: current.durationMinutes,
                                label: 'Active',
                                labelColor: _accent,
                              ),
                            if (current != null && next != null)
                              const SizedBox(height: 10),
                            if (next != null)
                              _PlanSummaryRow(
                                title: 'Next Session',
                                subject: next.subject,
                                durationMinutes: next.durationMinutes,
                                label: 'Up Next',
                                labelColor: _textSecondary,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              if (_trackedBlocks.isNotEmpty)
                ..._trackedBlocks.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TrackedPlanBlockTile(
                      block: entry.value,
                      statusLabel: _statusLabel(
                        entry.value.status,
                        isNextUpcoming:
                            entry.value.status == PlanBlockStatus.pending &&
                            _trackedBlocks.indexWhere(
                                  (b) => b.status == PlanBlockStatus.pending,
                                ) ==
                                entry.key,
                      ),
                      isUpdating: _updatingBlockIndexes.contains(entry.key),
                      isActive: entry.value.status == PlanBlockStatus.active,
                      isNextUpcoming:
                          entry.value.status == PlanBlockStatus.pending &&
                          _trackedBlocks.indexWhere(
                                (b) => b.status == PlanBlockStatus.pending,
                              ) ==
                              entry.key,
                      onDone:
                          (entry.value.status == PlanBlockStatus.pending ||
                              entry.value.status == PlanBlockStatus.active)
                          ? () => _updateBlockStatus(
                              index: entry.key,
                              status: PlanBlockStatus.completed,
                            )
                          : null,
                      onSkip:
                          (entry.value.status == PlanBlockStatus.pending ||
                              entry.value.status == PlanBlockStatus.active)
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
                  label: 'Start Session',
                  onPressed: _startStudySession,
                  fullWidth: true,
                ),
              ],
            ],
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
    required this.onDone,
    required this.onSkip,
    required this.isActive,
    required this.isNextUpcoming,
    this.isUpdating = false,
  });

  final TrackedPlanBlock block;
  final String statusLabel;
  final VoidCallback? onDone;
  final VoidCallback? onSkip;
  final bool isActive;
  final bool isNextUpcoming;
  final bool isUpdating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SectionContainer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? _InsightsDashboardScreenState._accent.withValues(alpha: 0.6)
                : _InsightsDashboardScreenState._cardElevated,
          ),
          color:
              block.status == PlanBlockStatus.completed ||
                  block.status == PlanBlockStatus.skipped
              ? _InsightsDashboardScreenState._card.withValues(alpha: 0.75)
              : isActive
              ? _InsightsDashboardScreenState._accent.withValues(alpha: 0.08)
              : _InsightsDashboardScreenState._card,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              block.type == PlanBlockType.study
                  ? Icons.menu_book_rounded
                  : Icons.free_breakfast_rounded,
              color: isActive
                  ? _InsightsDashboardScreenState._accent
                  : _InsightsDashboardScreenState._textSecondary,
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
                            color:
                                block.status == PlanBlockStatus.completed ||
                                    block.status == PlanBlockStatus.skipped
                                ? _InsightsDashboardScreenState._textSecondary
                                : _InsightsDashboardScreenState._textPrimary,
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
                          color:
                              (isActive
                                      ? _InsightsDashboardScreenState._accent
                                      : _InsightsDashboardScreenState
                                            ._cardElevated)
                                  .withValues(alpha: 0.25),
                        ),
                        child: Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 12,
                            color: isActive
                                ? _InsightsDashboardScreenState._accent
                                : _InsightsDashboardScreenState._textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${block.durationMinutes} min',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _InsightsDashboardScreenState._textSecondary,
                    ),
                  ),
                  if (isNextUpcoming) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Up Next',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        color: _InsightsDashboardScreenState._accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (onDone != null || onSkip != null)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isUpdating ? null : onDone,
                            child: const Text('Completed'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isUpdating ? null : onSkip,
                            child: const Text('Skip'),
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
                          color: _InsightsDashboardScreenState._textSecondary,
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

class _PlanSummaryRow extends StatelessWidget {
  const _PlanSummaryRow({
    required this.title,
    required this.subject,
    required this.durationMinutes,
    required this.label,
    required this.labelColor,
  });

  final String title;
  final String subject;
  final int durationMinutes;
  final String label;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _InsightsDashboardScreenState._textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$subject · $durationMinutes min',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _InsightsDashboardScreenState._textPrimary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: _InsightsDashboardScreenState._cardElevated,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: labelColor,
            ),
          ),
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _InsightsDashboardScreenState._cardElevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _InsightsDashboardScreenState._accent),
          const SizedBox(height: 6),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: _InsightsDashboardScreenState._textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _InsightsDashboardScreenState._textSecondary,
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
            color: _InsightsDashboardScreenState._textPrimary,
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
                        color: _InsightsDashboardScreenState._textSecondary,
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
                            color: _InsightsDashboardScreenState._accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dayShortLabel(point.day),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _InsightsDashboardScreenState._textSecondary,
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

class _SectionContainer extends StatelessWidget {
  const _SectionContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _InsightsDashboardScreenState._card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _InsightsDashboardScreenState._cardElevated,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _InsightsDashboardScreenState._accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
