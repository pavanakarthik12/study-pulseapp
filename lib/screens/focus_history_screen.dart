import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../core/theme.dart';
import 'widgets/modern_components.dart';

class FocusHistoryScreen extends StatelessWidget {
  const FocusHistoryScreen({super.key});

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) {
      return 'Just now';
    }
    final dt = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remSeconds = seconds % 60;
    return '${minutes}m ${remSeconds}s';
  }

  Color _scoreColor(double score) {
    if (score >= 75) {
      return const Color(0xFF4BD37B);
    }
    if (score >= 45) {
      return const Color(0xFFF2C94C);
    }
    return const Color(0xFFFF6B6B);
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('focus_sessions')
        .orderBy('timestamp', descending: true)
        .limit(10);

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: AppTheme.md),
                    Text(
                      'Focus History',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Latest 10 sessions for ML data verification',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: query.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load focus history right now.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No sessions yet. Complete a focus session to see data here.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final score =
                              (data['focus_score'] as num?)?.toDouble() ?? 0;
                          final duration =
                              (data['session_duration'] as num?)?.toInt() ?? 0;
                          final subject = (data['subject'] as String?)?.trim();
                          final ts = data['timestamp'] as Timestamp?;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.white.withValues(alpha: 0.1),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircularPercentIndicator(
                                  radius: 32,
                                  lineWidth: 7,
                                  percent: (score / 100).clamp(0.0, 1.0),
                                  animation: true,
                                  progressColor: _scoreColor(score),
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.13),
                                  center: Text(
                                    '${score.round()}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subject == null || subject.isEmpty
                                            ? 'General Focus Session'
                                            : subject,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Duration: ${_formatDuration(duration)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Colors.white
                                                  .withValues(alpha: 0.75),
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatTimestamp(ts),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.white
                                                  .withValues(alpha: 0.58),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
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