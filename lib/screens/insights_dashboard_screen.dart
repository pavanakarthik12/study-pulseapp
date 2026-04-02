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

  late Future<InsightsSummary> _insightsFuture;

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

  Future<InsightsSummary> _loadInsights() async {
    final sessions = await _insightsService.fetchRecentSessions();
    return _insightsService.buildInsightsSummary(sessions);
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
                FutureBuilder<InsightsSummary>(
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

                    final summary = snapshot.data ??
                        const InsightsSummary(
                          totalStudySeconds: 0,
                          averageFocusScore: 0,
                          bestSessionTimeLabel: 'No sessions yet',
                          bestFocusWindowLabel: 'Not enough data yet',
                          timeOfDayStats: <TimeOfDayStats>[],
                          totalSessions: 0,
                        );

                    return GlassCard(
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
