import 'package:flutter/material.dart';

import '../services/insights_service.dart';
import 'widgets/ui_shell.dart';

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
  List<PlanBlock> _planBlocks = const <PlanBlock>[];

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
    final sessions = await _insightsService.fetchRecentSessions();
    return _DashboardData(
      summary: _insightsService.buildInsightsSummary(sessions),
      weeklyTrend: _insightsService.buildRecentDailyTrend(sessions),
    );
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

  void _generatePlan() {
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

    setState(() {
      _planBlocks = blocks;
    });
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) {
      return '${minutes}m';
    }
    return '${hours}h ${minutes}m';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _insightsFuture = _loadInsights();
              });
              await _insightsFuture;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
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
                        );

                    final summary = payload.summary;

                    return Column(
                      children: [
                        GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: GradientActionButton(
                          label: 'Generate Auto Plan',
                          onPressed: _generatePlan,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                if (_planBlocks.isEmpty)
                  Text(
                    'No generated sessions yet. Add tasks and time range, then tap Generate Auto Plan.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                if (_planBlocks.isNotEmpty)
                  ..._planBlocks.map(
                    (block) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        child: Row(
                          children: [
                            Icon(
                              block.type == PlanBlockType.study
                                  ? Icons.menu_book_rounded
                                  : Icons.free_breakfast_rounded,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    block.type == PlanBlockType.study
                                        ? (block.subject ?? 'Study Session')
                                        : 'Short Break',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatTime(block.start)} - ${_formatTime(block.end)} • ${block.durationMinutes} min',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withValues(alpha: 0.75),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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
  });

  final InsightsSummary summary;
  final List<DailyTrendPoint> weeklyTrend;
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
