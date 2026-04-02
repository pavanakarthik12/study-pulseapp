import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FocusSessionRecord {
  const FocusSessionRecord({
    required this.focusScore,
    required this.durationSeconds,
    required this.timestamp,
    required this.userId,
    required this.completed,
    this.subject,
    this.distractionSeconds,
  });

  final double focusScore;
  final int durationSeconds;
  final DateTime? timestamp;
  final String? userId;
  final String? subject;
  final int? distractionSeconds;
  final bool completed;

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
      userId: (data['user_id'] as String?)?.trim(),
      subject: (data['subject'] as String?)?.trim(),
      distractionSeconds: (data['distraction_time'] as num?)?.toInt(),
      completed: (data['completed'] as bool?) ?? true,
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

class DailyTrendPoint {
  const DailyTrendPoint({
    required this.day,
    required this.totalStudySeconds,
    required this.averageFocusScore,
    required this.sessionCount,
  });

  final DateTime day;
  final int totalStudySeconds;
  final double averageFocusScore;
  final int sessionCount;
}

enum PlanBlockType { study, shortBreak }

enum PlanBlockStatus { pending, done, skipped }

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

class TrackedPlanBlock {
  const TrackedPlanBlock({
    required this.subject,
    required this.durationMinutes,
    required this.status,
    this.type = PlanBlockType.study,
  });

  final String subject;
  final int durationMinutes;
  final PlanBlockStatus status;
  final PlanBlockType type;

  TrackedPlanBlock copyWith({PlanBlockStatus? status}) {
    return TrackedPlanBlock(
      subject: subject,
      durationMinutes: durationMinutes,
      status: status ?? this.status,
      type: type,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'subject': subject,
      'duration_minutes': durationMinutes,
      'status': status.name,
      'type': type.name,
    };
  }
}

class TrackedStudyPlan {
  const TrackedStudyPlan({
    required this.id,
    required this.userId,
    required this.blocks,
  });

  final String id;
  final String userId;
  final List<TrackedPlanBlock> blocks;
}

class StreakData {
  const StreakData({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastSessionDate,
    required this.hasSevenDayBadge,
    required this.hasThirtyDayBadge,
  });

  final int currentStreak;
  final int longestStreak;
  final DateTime? lastSessionDate;
  final bool hasSevenDayBadge;
  final bool hasThirtyDayBadge;

  factory StreakData.fromMap(Map<String, dynamic> data) {
    final rawLastSession = data['last_session_date'];
    DateTime? lastSessionDate;
    if (rawLastSession is Timestamp) {
      lastSessionDate = rawLastSession.toDate();
    }

    return StreakData(
      currentStreak: (data['current_streak'] as num?)?.toInt() ?? 0,
      longestStreak: (data['longest_streak'] as num?)?.toInt() ?? 0,
      lastSessionDate: lastSessionDate,
      hasSevenDayBadge: (data['has_seven_day_badge'] as bool?) ?? false,
      hasThirtyDayBadge: (data['has_thirty_day_badge'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'last_session_date': lastSessionDate == null
          ? null
          : Timestamp.fromDate(lastSessionDate!),
      'has_seven_day_badge': hasSevenDayBadge,
      'has_thirty_day_badge': hasThirtyDayBadge,
    };
  }
}

class WeeklyGoal {
  const WeeklyGoal({
    required this.targetSessions,
    required this.currentWeekSessionCount,
    required this.weekStartDate,
  });

  final int targetSessions;
  final int currentWeekSessionCount;
  final DateTime weekStartDate;

  bool get isCompleted => currentWeekSessionCount >= targetSessions;

  factory WeeklyGoal.fromMap(Map<String, dynamic> data) {
    final rawWeekStart = data['week_start_date'];
    DateTime weekStartDate = DateTime.now();
    if (rawWeekStart is Timestamp) {
      weekStartDate = rawWeekStart.toDate();
    }

    return WeeklyGoal(
      targetSessions: (data['target_sessions'] as num?)?.toInt() ?? 5,
      currentWeekSessionCount:
          (data['current_week_session_count'] as num?)?.toInt() ?? 0,
      weekStartDate: weekStartDate,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'target_sessions': targetSessions,
      'current_week_session_count': currentWeekSessionCount,
      'week_start_date': Timestamp.fromDate(weekStartDate),
    };
  }
}

class InsightsService {
  InsightsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _plansCollection =>
      _firestore.collection('study_plans');

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
      (total, session) => total + session.durationSeconds,
    );

    final avgFocus = sessions.fold<double>(
          0,
          (total, session) => total + session.focusScore,
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

  List<DailyTrendPoint> buildRecentDailyTrend(
    List<FocusSessionRecord> sessions, {
    int days = 7,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDay = today.subtract(Duration(days: days - 1));

    final dayBuckets = <DateTime, _DailyAccumulator>{};
    for (var i = 0; i < days; i++) {
      final day = firstDay.add(Duration(days: i));
      dayBuckets[day] = _DailyAccumulator();
    }

    for (final session in sessions) {
      final ts = session.timestamp;
      if (ts == null) {
        continue;
      }

      final dayKey = DateTime(ts.year, ts.month, ts.day);
      final bucket = dayBuckets[dayKey];
      if (bucket == null) {
        continue;
      }

      bucket.totalStudySeconds += session.durationSeconds;
      bucket.totalFocusScore += session.focusScore;
      bucket.sessionCount += 1;
    }

    return dayBuckets.entries.map((entry) {
      final bucket = entry.value;
      final averageFocus = bucket.sessionCount == 0
          ? 0.0
          : bucket.totalFocusScore / bucket.sessionCount;

      return DailyTrendPoint(
        day: entry.key,
        totalStudySeconds: bucket.totalStudySeconds,
        averageFocusScore: averageFocus,
        sessionCount: bucket.sessionCount,
      );
    }).toList();
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

  Future<TrackedStudyPlan> createStudyPlan({
    required String userId,
    required List<PlanBlock> blocks,
  }) async {
    final trackedBlocks = blocks
        .map(
          (block) => TrackedPlanBlock(
            subject: block.subject ?? 'Short Break',
            durationMinutes: block.durationMinutes,
            status: PlanBlockStatus.pending,
            type: block.type,
          ),
        )
        .toList();

    final planPayload = <String, dynamic>{
      'user_id': userId,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'blocks': trackedBlocks.map((block) => block.toMap()).toList(),
    };

    final docRef = await _plansCollection.add(planPayload);

    return TrackedStudyPlan(
      id: docRef.id,
      userId: userId,
      blocks: trackedBlocks,
    );
  }

  Future<void> updateBlockStatus({
    required String planId,
    required int blockIndex,
    required PlanBlockStatus status,
    required List<TrackedPlanBlock> blocks,
  }) async {
    if (blockIndex < 0 || blockIndex >= blocks.length) {
      return;
    }

    final updatedBlocks = <TrackedPlanBlock>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      updatedBlocks.add(
        index == blockIndex ? block.copyWith(status: status) : block,
      );
    }

    await _plansCollection.doc(planId).update({
      'updated_at': FieldValue.serverTimestamp(),
      'blocks': updatedBlocks.map((block) => block.toMap()).toList(),
    });
  }

  StreakData calculateStreakFromSessions(List<FocusSessionRecord> sessions) {
    if (sessions.isEmpty) {
      return const StreakData(
        currentStreak: 0,
        longestStreak: 0,
        lastSessionDate: null,
        hasSevenDayBadge: false,
        hasThirtyDayBadge: false,
      );
    }

    final sortedSessions = [...sessions]
      ..sort((a, b) => (b.timestamp ?? DateTime(1)).compareTo(a.timestamp ?? DateTime(1)));

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final sessionDayBuckets = <DateTime, bool>{};
    for (final session in sortedSessions) {
      final ts = session.timestamp;
      if (ts == null) continue;
      final day = DateTime(ts.year, ts.month, ts.day);
      sessionDayBuckets[day] = true;
    }

    int currentStreak = 0;
    int longestStreak = 0;
    DateTime? lastSessionDate;

    var checkDate = todayStart;
    for (var i = 0; i < 365; i++) {
      if (sessionDayBuckets[checkDate] == true) {
        currentStreak += 1;
        lastSessionDate ??= checkDate;
      } else {
        if (currentStreak > longestStreak) {
          longestStreak = currentStreak;
        }
        currentStreak = 0;
      }
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    if (currentStreak > longestStreak) {
      longestStreak = currentStreak;
    }

    return StreakData(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      lastSessionDate: lastSessionDate,
      hasSevenDayBadge: longestStreak >= 7,
      hasThirtyDayBadge: longestStreak >= 30,
    );
  }

  WeeklyGoal calculateWeeklyGoal(List<FocusSessionRecord> sessions) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final weekEndDate = weekStartDate.add(const Duration(days: 7));

    int thisWeekSessionCount = 0;
    for (final session in sessions) {
      final ts = session.timestamp;
      if (ts == null) continue;
      if (ts.isAfter(weekStartDate) && ts.isBefore(weekEndDate)) {
        thisWeekSessionCount += 1;
      }
    }

    return WeeklyGoal(
      targetSessions: 5,
      currentWeekSessionCount: thisWeekSessionCount,
      weekStartDate: weekStartDate,
    );
  }

  Future<StreakData> fetchStreakData(String userId) async {
    try {
      final doc = await _firestore.collection('user_streaks').doc(userId).get();
      if (doc.exists) {
        return StreakData.fromMap(doc.data() ?? {});
      }
    } catch (_) {}

    return const StreakData(
      currentStreak: 0,
      longestStreak: 0,
      lastSessionDate: null,
      hasSevenDayBadge: false,
      hasThirtyDayBadge: false,
    );
  }

  Future<void> updateStreakData(String userId, StreakData streak) async {
    try {
      await _firestore.collection('user_streaks').doc(userId).set(
            <String, dynamic>{
              'user_id': userId,
              ...streak.toMap(),
              'updated_at': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
    } catch (_) {}
  }

  Future<WeeklyGoal> fetchWeeklyGoal(String userId) async {
    try {
      final doc = await _firestore.collection('user_goals').doc(userId).get();
      if (doc.exists) {
        return WeeklyGoal.fromMap(doc.data() ?? {});
      }
    } catch (_) {}

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    return WeeklyGoal(
      targetSessions: 5,
      currentWeekSessionCount: 0,
      weekStartDate: weekStart,
    );
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

  /// Exports focus sessions as CSV for ML training datasets.
  /// Returns CSV formatted string with headers and session data.
  Future<String> exportSessionsAsCSV({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _firestore
          .collection('focus_sessions')
          .where('user_id', isEqualTo: userId);

      if (startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: startDate);
      }

      if (endDate != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: endDate);
      }

      final snapshot = await query.orderBy('timestamp').get();
      final sessions =
          snapshot.docs.map((doc) => FocusSessionRecord.fromMap(doc.data())).toList();

      if (sessions.isEmpty) {
        return 'user_id,subject,session_duration,focus_score,distraction_time,completed,timestamp\n';
      }

      final buffer = StringBuffer();
      buffer.writeln(
          'user_id,subject,session_duration,focus_score,distraction_time,completed,timestamp');

      for (final session in sessions) {
        final timestamp = session.timestamp?.toIso8601String() ?? '';
        final csvLine =
            '"${session.userId}","${session.subject ?? 'N/A'}",${session.durationSeconds},${session.focusScore.toStringAsFixed(2)},${session.distractionSeconds ?? 0},${session.completed},"$timestamp"';
        buffer.writeln(csvLine);
      }

      return buffer.toString();
    } catch (_) {
      return '';
    }
  }

  /// Exports focus sessions as JSON for ML training datasets.
  Future<String> exportSessionsAsJSON({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _firestore
          .collection('focus_sessions')
          .where('user_id', isEqualTo: userId);

      if (startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: startDate);
      }

      if (endDate != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: endDate);
      }

      final snapshot = await query.orderBy('timestamp').get();
      final sessionsList = snapshot.docs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'user_id': data['user_id'],
          'subject': data['subject'],
          'session_duration': data['session_duration'],
          'focus_score': data['focus_score'],
          'distraction_time': data['distraction_time'],
          'completed': data['completed'],
          'timestamp': data['timestamp'] is Timestamp
              ? (data['timestamp'] as Timestamp).toDate().toIso8601String()
              : data['timestamp'],
        };
      }).toList();

      return _jsonEncodeDataset(sessionsList);
    } catch (_) {
      return '[]';
    }
  }

  String _jsonEncodeDataset(List<Map<String, dynamic>> sessions) {
    final buffer = StringBuffer('[\n');
    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      buffer.write('  ');
      buffer.write(_encodeJsonMap(session));
      if (i < sessions.length - 1) {
        buffer.write(',');
      }
      buffer.writeln();
    }
    buffer.write(']');
    return buffer.toString();
  }

  String _encodeJsonMap(Map<String, dynamic> map) {
    final entries = map.entries.map((e) {
      final key = e.key;
      final value = e.value;
      final encodedValue = value is String ? '"${value.replaceAll('"', '\\"')}"' : value;
      return '"$key":$encodedValue';
    });
    return '{${entries.join(',')}}';
  }
}

class _DailyAccumulator {
  int totalStudySeconds = 0;
  double totalFocusScore = 0;
  int sessionCount = 0;
}
