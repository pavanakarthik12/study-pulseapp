import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FocusSessionRecord {
  const FocusSessionRecord({
    required this.focusScore,
    required this.durationSeconds,
    required this.timestamp,
    this.subject,
  });

  final double focusScore;
  final int durationSeconds;
  final DateTime? timestamp;
  final String? subject;

  factory FocusSessionRecord.fromMap(Map<String, dynamic> data) {
    final rawTimestamp = data['timestamp'] ?? data['session_started_at'];
    DateTime? parsedTimestamp;
    if (rawTimestamp is Timestamp) {
      parsedTimestamp = rawTimestamp.toDate();
    }

    return FocusSessionRecord(
      focusScore: (data['focus_score'] as num?)?.toDouble() ?? 0,
      durationSeconds: (data['session_duration'] as num?)?.toInt() ?? 0,
      timestamp: parsedTimestamp,
      subject: (data['subject'] as String?)?.trim(),
    );
  }
}

class TimeOfDayStats {
  const TimeOfDayStats({
    required this.label,
    required this.averageFocusScore,
    required this.sessionCount,
  });

  final String label;
  final double averageFocusScore;
  final int sessionCount;
}

class InsightsSummary {
  const InsightsSummary({
    required this.totalStudySeconds,
    required this.averageFocusScore,
    required this.bestSessionTimeLabel,
    required this.bestFocusWindowLabel,
    required this.timeOfDayStats,
    required this.totalSessions,
  });

  final int totalStudySeconds;
  final double averageFocusScore;
  final String bestSessionTimeLabel;
  final String bestFocusWindowLabel;
  final List<TimeOfDayStats> timeOfDayStats;
  final int totalSessions;
}

enum PlanBlockType { study, shortBreak }

class PlanBlock {
  const PlanBlock({
    required this.type,
    required this.start,
    required this.end,
    this.subject,
  });

  final PlanBlockType type;
  final DateTime start;
  final DateTime end;
  final String? subject;

  int get durationMinutes => end.difference(start).inMinutes;
}

class InsightsService {
  InsightsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<FocusSessionRecord>> fetchRecentSessions({int limit = 160}) async {
    final query = _firestore
        .collection('focus_sessions')
        .orderBy('timestamp', descending: true)
        .limit(limit);

    final snapshot = await query.get();

    return snapshot.docs
        .map((doc) => FocusSessionRecord.fromMap(doc.data()))
        .toList();
  }

  InsightsSummary buildInsightsSummary(List<FocusSessionRecord> sessions) {
    if (sessions.isEmpty) {
      return const InsightsSummary(
        totalStudySeconds: 0,
        averageFocusScore: 0,
        bestSessionTimeLabel: 'No sessions yet',
        bestFocusWindowLabel: 'Not enough data yet',
        timeOfDayStats: <TimeOfDayStats>[],
        totalSessions: 0,
      );
    }

    final validSessions = sessions.where((session) => session.durationSeconds > 0);
    final totalStudySeconds = validSessions.fold<int>(
      0,
      (sum, session) => sum + session.durationSeconds,
    );

    final avgFocus = sessions.fold<double>(
          0,
          (sum, session) => sum + session.focusScore,
        ) /
        sessions.length;

    final bestSession = sessions.reduce((a, b) {
      return a.focusScore >= b.focusScore ? a : b;
    });

    final bestSessionTime = bestSession.timestamp;
    final bestSessionLabel = bestSessionTime == null
        ? 'Unknown time'
        : _formatHourRange(bestSessionTime.hour, windowSize: 1);

    final hourBuckets = <int, List<double>>{};
    final dayPartBuckets = <String, List<double>>{};

    for (final session in sessions) {
      final ts = session.timestamp;
      if (ts == null) {
        continue;
      }

      hourBuckets.putIfAbsent(ts.hour, () => <double>[]).add(session.focusScore);

      final segment = _segmentForHour(ts.hour);
      dayPartBuckets.putIfAbsent(segment, () => <double>[]).add(session.focusScore);
    }

    final bestWindow = _bestTwoHourWindow(hourBuckets);
    final bestWindowLabel = bestWindow == null
        ? 'Not enough data yet'
        : 'You focus best at ${_formatHourRange(bestWindow, windowSize: 2)}';

    const orderedSegments = <String>['Morning', 'Afternoon', 'Evening', 'Night'];
    final timeOfDayStats = <TimeOfDayStats>[];
    for (final segment in orderedSegments) {
      final scores = dayPartBuckets[segment];
      if (scores == null || scores.isEmpty) {
        continue;
      }
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      timeOfDayStats.add(
        TimeOfDayStats(
          label: segment,
          averageFocusScore: avg,
          sessionCount: scores.length,
        ),
      );
    }

    return InsightsSummary(
      totalStudySeconds: totalStudySeconds,
      averageFocusScore: avgFocus,
      bestSessionTimeLabel: bestSessionLabel,
      bestFocusWindowLabel: bestWindowLabel,
      timeOfDayStats: timeOfDayStats,
      totalSessions: sessions.length,
    );
  }

  List<PlanBlock> generatePlan({
    required List<String> subjects,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
  }) {
    final normalizedSubjects = subjects
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    final now = DateTime.now();
    var cursor = DateTime(
      now.year,
      now.month,
      now.day,
      startTime.hour,
      startTime.minute,
    );

    var end = DateTime(
      now.year,
      now.month,
      now.day,
      endTime.hour,
      endTime.minute,
    );

    if (!end.isAfter(cursor)) {
      end = end.add(const Duration(days: 1));
    }

    final totalMinutes = end.difference(cursor).inMinutes;
    if (totalMinutes < 25) {
      return const <PlanBlock>[];
    }

    final studyMinutes = _selectStudyDuration(totalMinutes);
    final breakMinutes = totalMinutes >= 180 ? 10 : 5;

    final blocks = <PlanBlock>[];
    var taskIndex = 0;

    while (end.difference(cursor).inMinutes >= 25) {
      final remaining = end.difference(cursor).inMinutes;
      final nextStudyMinutes = remaining >= studyMinutes
          ? studyMinutes
          : (remaining >= 45 ? 45 : remaining);

      if (nextStudyMinutes < 25) {
        break;
      }

      final studyEnd = cursor.add(Duration(minutes: nextStudyMinutes));
      blocks.add(
        PlanBlock(
          type: PlanBlockType.study,
          start: cursor,
          end: studyEnd,
          subject: normalizedSubjects.isEmpty
              ? 'General Focus'
              : normalizedSubjects[taskIndex % normalizedSubjects.length],
        ),
      );

      cursor = studyEnd;
      taskIndex += 1;

      final remainingAfterStudy = end.difference(cursor).inMinutes;
      if (remainingAfterStudy < 30) {
        break;
      }

      if (remainingAfterStudy >= breakMinutes + 25) {
        final breakEnd = cursor.add(Duration(minutes: breakMinutes));
        blocks.add(
          PlanBlock(
            type: PlanBlockType.shortBreak,
            start: cursor,
            end: breakEnd,
          ),
        );
        cursor = breakEnd;
      }
    }

    return blocks;
  }

  int _selectStudyDuration(int totalMinutes) {
    if (totalMinutes <= 90) {
      return 25;
    }
    if (totalMinutes <= 180) {
      return 30;
    }
    if (totalMinutes <= 300) {
      return 35;
    }
    return 40;
  }

  int? _bestTwoHourWindow(Map<int, List<double>> hourBuckets) {
    if (hourBuckets.isEmpty) {
      return null;
    }

    int? bestStartHour;
    double bestScore = -1;

    for (var hour = 0; hour < 24; hour++) {
      final firstHourScores = hourBuckets[hour] ?? const <double>[];
      final secondHourScores = hourBuckets[(hour + 1) % 24] ?? const <double>[];

      final merged = <double>[...firstHourScores, ...secondHourScores];
      if (merged.isEmpty) {
        continue;
      }

      final avg = merged.reduce((a, b) => a + b) / merged.length;
      if (avg > bestScore) {
        bestScore = avg;
        bestStartHour = hour;
      }
    }

    return bestStartHour;
  }

  String _segmentForHour(int hour) {
    if (hour >= 5 && hour < 12) {
      return 'Morning';
    }
    if (hour >= 12 && hour < 17) {
      return 'Afternoon';
    }
    if (hour >= 17 && hour < 22) {
      return 'Evening';
    }
    return 'Night';
  }

  String _formatHourRange(int startHour, {required int windowSize}) {
    final start = _formatHour(startHour);
    final end = _formatHour((startHour + windowSize) % 24);
    return '$start-$end';
  }

  String _formatHour(int hour24) {
    final normalized = hour24 % 24;
    final hour12 = normalized % 12 == 0 ? 12 : normalized % 12;
    final suffix = normalized >= 12 ? 'PM' : 'AM';
    return '$hour12 $suffix';
  }
}
