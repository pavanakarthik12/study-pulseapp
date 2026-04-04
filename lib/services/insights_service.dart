import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FocusSessionRecord {
  const FocusSessionRecord({
    required this.focusScore,
    required this.durationSeconds,
    required this.timestamp,
    required this.userId,
    required this.completed,
    required this.status,
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
  final String status;

  factory FocusSessionRecord.fromMap(Map<String, dynamic> data) {
    final rawTimestamp = data['timestamp'] ?? data['session_started_at'];
    DateTime? parsedTimestamp;
    if (rawTimestamp is Timestamp) {
      parsedTimestamp = rawTimestamp.toDate();
    } else if (rawTimestamp is String) {
      parsedTimestamp = DateTime.tryParse(rawTimestamp);
    }

    return FocusSessionRecord(
      focusScore: (data['focus_score'] as num?)?.toDouble() ?? 0,
      durationSeconds:
          (data['session_duration'] as num?)?.toInt() ??
          (data['total_duration_seconds'] as num?)?.toInt() ??
          (data['duration_seconds'] as num?)?.toInt() ??
          0,
      timestamp: parsedTimestamp,
      userId: (data['user_id'] as String?)?.trim(),
      subject: (data['subject'] as String?)?.trim(),
      distractionSeconds: (data['distraction_time'] as num?)?.toInt(),
      completed: (data['completed'] as bool?) ??
          ((data['status'] as String?)?.toLowerCase() == 'completed'),
      status: ((data['status'] as String?)?.toLowerCase() ??
              ((data['completed'] as bool?) == true ? 'completed' : 'pending')),
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

enum PlanBlockStatus { pending, active, completed, skipped }

PlanBlockStatus _statusFromName(String? raw) {
  switch (raw) {
    case 'active':
    case 'running':
    case 'paused':
      return PlanBlockStatus.active;
    case 'completed':
    case 'done':
      return PlanBlockStatus.completed;
    case 'skipped':
      return PlanBlockStatus.skipped;
    default:
      return PlanBlockStatus.pending;
  }
}

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
    required this.orderIndex,
    this.type = PlanBlockType.study,
  });

  final String subject;
  final int durationMinutes;
  final PlanBlockStatus status;
  final PlanBlockType type;
  final int orderIndex;

  TrackedPlanBlock copyWith({PlanBlockStatus? status}) {
    return TrackedPlanBlock(
      subject: subject,
      durationMinutes: durationMinutes,
      status: status ?? this.status,
      type: type,
      orderIndex: orderIndex,
    );
  }

  factory TrackedPlanBlock.fromMap(
    Map<String, dynamic> data, {
    required int fallbackOrderIndex,
  }) {
    final rawType = data['type'] as String?;
    final rawOrderIndex = (data['order_index'] as num?)?.toInt();

    return TrackedPlanBlock(
      subject: (data['subject'] as String?)?.trim().isNotEmpty == true
          ? (data['subject'] as String).trim()
          : 'General Focus',
      durationMinutes: (data['duration_minutes'] as num?)?.toInt() ?? 25,
      status: _statusFromName(data['status'] as String?),
      type: rawType == 'shortBreak'
          ? PlanBlockType.shortBreak
          : PlanBlockType.study,
      orderIndex: rawOrderIndex ?? fallbackOrderIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'subject': subject,
      'duration_minutes': durationMinutes,
      'status': status.name,
      'type': type.name,
      'order_index': orderIndex,
    };
  }
}

class TrackedStudyPlan {
  const TrackedStudyPlan({
    required this.id,
    required this.userId,
    required this.blocks,
    this.currentBlockIndex,
    this.planStatus,
  });

  final String id;
  final String userId;
  final List<TrackedPlanBlock> blocks;
  final int? currentBlockIndex;
  final String? planStatus;

  factory TrackedStudyPlan.fromDoc(String docId, Map<String, dynamic> data) {
    final rawBlocks = (data['blocks'] as List?) ?? const [];
    final blocks =
        rawBlocks
            .asMap()
            .entries
            .map(
              (entry) => TrackedPlanBlock.fromMap(
                entry.value as Map<String, dynamic>,
                fallbackOrderIndex: entry.key,
              ),
            )
            .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return TrackedStudyPlan(
      id: docId,
      userId: (data['user_id'] as String?)?.trim() ?? '',
      blocks: blocks,
      currentBlockIndex: (data['current_block_index'] as num?)?.toInt(),
      planStatus: data['plan_status'] as String?,
    );
  }
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

class SessionRecordInput {
  const SessionRecordInput({
    required this.userId,
    required this.sessionDurationSeconds,
    required this.focusScore,
    required this.timestamp,
    required this.subject,
    required this.completed,
    this.planId,
    this.status,
    this.blockIndex,
    this.blockType,
  });

  final String userId;
  final int sessionDurationSeconds;
  final double focusScore;
  final DateTime timestamp;
  final String subject;
  final bool completed;
  final String? planId;
  final String? status;
  final int? blockIndex;
  final String? blockType;
}

class SessionPreview {
  const SessionPreview({
    required this.subject,
    required this.durationMinutes,
    required this.planId,
  });

  final String subject;
  final int durationMinutes;
  final String? planId;
}

class SessionFlowState {
  const SessionFlowState({
    required this.upcoming,
    required this.current,
    required this.recent,
  });

  const SessionFlowState.empty()
    : upcoming = null,
      current = null,
      recent = const <FocusSessionRecord>[];

  final SessionPreview? upcoming;
  final SessionPreview? current;
  final List<FocusSessionRecord> recent;
}

class InsightsService {
  InsightsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final StreamController<String> _sessionUpdatesController =
      StreamController<String>.broadcast();

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _plansCollection =>
      _firestore.collection('study_plans');

  CollectionReference<Map<String, dynamic>> get _sessionsCollection =>
      _firestore.collection('focus_sessions');

  static Stream<String> watchSessionUpdates() =>
      _sessionUpdatesController.stream;

  static void disposeSyncControllers() {
    _sessionUpdatesController.close();
  }

  void _notifySessionUpdated(String userId) {
    if (!_sessionUpdatesController.isClosed) {
      _sessionUpdatesController.add(userId);
    }
  }

  Future<void> saveSessionRecord(SessionRecordInput input) async {
    final resolvedStatus =
        (input.status?.trim().toLowerCase().isNotEmpty ?? false)
        ? input.status!.trim().toLowerCase()
        : (input.completed ? 'completed' : 'skipped');

    final payload = <String, dynamic>{
      'user_id': input.userId,
      'session_duration': input.sessionDurationSeconds,
      'focus_score': input.focusScore,
      'timestamp': Timestamp.fromDate(input.timestamp),
      'subject': input.subject,
      'completed': input.completed,
      'status': resolvedStatus,
      'plan_id': input.planId,
      if (input.blockIndex != null) 'block_index': input.blockIndex,
      if (input.blockType != null) 'block_type': input.blockType,
      // Compatibility mirrors for older readers.
      'total_duration_seconds': input.sessionDurationSeconds,
      'session_started_at': Timestamp.fromDate(input.timestamp),
    };

    await _sessionsCollection.add(payload);
    _notifySessionUpdated(input.userId);
  }

  Future<List<FocusSessionRecord>> fetchRecentSessions({
    int limit = 160,
    String? userId,
    bool completedOnly = false,
  }) async {
    Query<Map<String, dynamic>> query = _sessionsCollection
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('user_id', isEqualTo: userId);
    }

    final snapshot = await query.get();

    final sessions = snapshot.docs
        .map((doc) => FocusSessionRecord.fromMap(doc.data()))
        .toList();

    if (completedOnly) {
      return sessions.where((session) => session.completed).toList();
    }

    return sessions;
  }

  Stream<List<FocusSessionRecord>> watchRecentSessions({
    int limit = 160,
    required String userId,
  }) {
    final query = _sessionsCollection
        .where('user_id', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit);

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => FocusSessionRecord.fromMap(doc.data()))
          .toList(),
    );
  }

  Future<SessionFlowState> fetchSessionFlowState(
    String userId, {
    int recentLimit = 5,
  }) async {
    try {
      final recent = await fetchRecentSessions(
        limit: recentLimit,
        userId: userId,
      );

      final queueSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('timer_queue_state')
          .get();

      SessionPreview? current;
      SessionPreview? upcoming;

      final queueDocs = [...queueSnapshot.docs]
        ..sort((a, b) {
          final aTs = a.data()['updated_at'];
          final bTs = b.data()['updated_at'];
          final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
          final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
          return bMs.compareTo(aMs);
        });

      for (final doc in queueDocs) {
        final data = doc.data();
        final planStatus = (data['plan_status'] as String?)?.toLowerCase();
        if (planStatus == 'completed') {
          continue;
        }

        final blocks = (data['all_blocks'] as List?) ?? const [];
        final currentIndex =
            (data['current_block_index'] as num?)?.toInt() ?? 0;
        final planId = data['plan_id'] as String?;

        if (blocks.isEmpty || currentIndex < 0 || currentIndex > blocks.length) {
          continue;
        }

        if (currentIndex < blocks.length) {
          final currentBlock = blocks[currentIndex] as Map<String, dynamic>;
          final state = (currentBlock['state'] as String?) ?? 'pending';
          final subject = (currentBlock['subject'] as String?)?.trim();
          final durationSeconds =
              (currentBlock['duration_seconds'] as num?)?.toInt() ?? 0;

          if (state == 'running' || state == 'paused') {
            current = SessionPreview(
              subject: (subject == null || subject.isEmpty)
                  ? 'Smart Session'
                  : subject,
              durationMinutes: durationSeconds ~/ 60,
              planId: planId,
            );
          }
        }

        for (var i = currentIndex.clamp(0, blocks.length - 1); i < blocks.length; i++) {
          final block = blocks[i] as Map<String, dynamic>;
          final blockState = (block['state'] as String?) ?? 'pending';
          final blockType = (block['type'] as String?) ?? 'study';

          if (blockState == 'pending' && blockType == 'study') {
            final upSubject = (block['subject'] as String?)?.trim();
            final upDuration =
                (block['duration_seconds'] as num?)?.toInt() ?? 0;
            upcoming = SessionPreview(
              subject: (upSubject == null || upSubject.isEmpty)
                  ? 'Upcoming Session'
                  : upSubject,
              durationMinutes: upDuration ~/ 60,
              planId: planId,
            );
            break;
          }
        }

        if (current != null || upcoming != null) {
          break;
        }
      }

      if (current == null || upcoming == null) {
        final latestPlan = await fetchLatestPlan(userId);
        if (latestPlan != null) {
          TrackedPlanBlock? currentBlock;
          TrackedPlanBlock? upcomingBlock;

          for (final block in latestPlan.blocks) {
            if (currentBlock == null &&
                block.status == PlanBlockStatus.active) {
              currentBlock = block;
            }
            if (upcomingBlock == null &&
                block.status == PlanBlockStatus.pending) {
              upcomingBlock = block;
            }
            if (currentBlock != null && upcomingBlock != null) {
              break;
            }
          }

          if (current == null && currentBlock != null) {
            current = SessionPreview(
              subject: currentBlock.subject,
              durationMinutes: currentBlock.durationMinutes,
              planId: latestPlan.id,
            );
          }

          if (upcoming == null && upcomingBlock != null) {
            upcoming = SessionPreview(
              subject: upcomingBlock.subject,
              durationMinutes: upcomingBlock.durationMinutes,
              planId: latestPlan.id,
            );
          }
        }
      }

      return SessionFlowState(
        upcoming: upcoming,
        current: current,
        recent: recent,
      );
    } catch (_) {
      return const SessionFlowState.empty();
    }
  }

  Stream<SessionFlowState> watchSessionFlowState(
    String userId, {
    int recentLimit = 5,
  }) {
    return Stream<SessionFlowState>.multi((controller) {
      Future<void> push() async {
        try {
          final state = await fetchSessionFlowState(
            userId,
            recentLimit: recentLimit,
          );
          if (!controller.isClosed) {
            controller.add(state);
          }
        } catch (_) {
          if (!controller.isClosed) {
            controller.add(const SessionFlowState.empty());
          }
        }
      }

      final queueSub = _firestore
          .collection('users')
          .doc(userId)
          .collection('timer_queue_state')
          .snapshots()
          .listen((_) => unawaited(push()));

      final planSub = _plansCollection
          .where('user_id', isEqualTo: userId)
          .limit(10)
          .snapshots()
          .listen((_) => unawaited(push()));

      unawaited(push());

      controller
        ..onCancel = () async {
          await queueSub.cancel();
          await planSub.cancel();
        };
    });
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

    final completedSessions = sessions
        .where((session) => session.completed)
        .toList();

    if (completedSessions.isEmpty) {
      return const InsightsSummary(
        totalStudySeconds: 0,
        averageFocusScore: 0,
        bestSessionTimeLabel: 'No completed sessions yet',
        bestFocusWindowLabel: 'Complete a session to unlock insights',
        timeOfDayStats: <TimeOfDayStats>[],
        totalSessions: 0,
      );
    }

    final validSessions = completedSessions.where(
      (session) => session.durationSeconds > 0,
    );
    final totalStudySeconds = validSessions.fold<int>(
      0,
      (total, session) => total + session.durationSeconds,
    );

    final avgFocus =
        completedSessions.fold<double>(
          0,
          (total, session) => total + session.focusScore,
        ) /
        completedSessions.length;

    final bestSession = completedSessions.reduce((a, b) {
      return a.focusScore >= b.focusScore ? a : b;
    });

    final bestSessionTime = bestSession.timestamp;
    final bestSessionLabel = bestSessionTime == null
        ? 'Unknown time'
        : _formatHourRange(bestSessionTime.hour, windowSize: 1);

    final hourBuckets = <int, List<double>>{};
    final dayPartBuckets = <String, List<double>>{};

    for (final session in completedSessions) {
      final ts = session.timestamp;
      if (ts == null) {
        continue;
      }

      hourBuckets
          .putIfAbsent(ts.hour, () => <double>[])
          .add(session.focusScore);

      final segment = _segmentForHour(ts.hour);
      dayPartBuckets
          .putIfAbsent(segment, () => <double>[])
          .add(session.focusScore);
    }

    final bestWindow = _bestTwoHourWindow(hourBuckets);
    final bestWindowLabel = bestWindow == null
        ? 'Not enough data yet'
        : 'You focus best at ${_formatHourRange(bestWindow, windowSize: 2)}';

    const orderedSegments = <String>[
      'Morning',
      'Afternoon',
      'Evening',
      'Night',
    ];
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
      totalSessions: completedSessions.length,
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

    for (final session in sessions.where((item) => item.completed)) {
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

    final planPayload = <String, dynamic>{
      'user_id': userId,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'plan_status': 'active',
      'is_active': true,
      'current_block_index': 0,
      'blocks': trackedBlocks.map((block) => block.toMap()).toList(),
    };

    final docRef = await _plansCollection.add(planPayload);

    return TrackedStudyPlan(
      id: docRef.id,
      userId: userId,
      blocks: trackedBlocks,
      currentBlockIndex: 0,
      planStatus: 'active',
    );
  }

  Stream<TrackedStudyPlan?> watchStudyPlan(String planId) {
    return _plansCollection.doc(planId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) {
        return null;
      }
      return TrackedStudyPlan.fromDoc(doc.id, data);
    });
  }

  Future<TrackedStudyPlan?> fetchLatestPlan(String userId) async {
    final snapshot = await _plansCollection
        .where('user_id', isEqualTo: userId)
        .orderBy('updated_at', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final doc = snapshot.docs.first;
    return TrackedStudyPlan.fromDoc(doc.id, doc.data());
  }

  Future<TrackedStudyPlan?> fetchPlanById(String planId) async {
    final doc = await _plansCollection.doc(planId).get();
    final data = doc.data();
    if (!doc.exists || data == null) {
      return null;
    }

    return TrackedStudyPlan.fromDoc(doc.id, data);
  }

  Future<void> syncPlanSchedule({
    required String planId,
    required List<TrackedPlanBlock> blocks,
    int? currentBlockIndex,
    String? planStatus,
    bool? isActive,
    DateTime? endedAt,
  }) async {
    await _plansCollection.doc(planId).set({
      'updated_at': FieldValue.serverTimestamp(),
      'blocks': blocks.map((block) => block.toMap()).toList(),
      if (currentBlockIndex != null) 'current_block_index': currentBlockIndex,
      if (planStatus != null) 'plan_status': planStatus,
      if (isActive != null) 'is_active': isActive,
      if (endedAt != null) 'end_timestamp': Timestamp.fromDate(endedAt),
    }, SetOptions(merge: true));
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
      ..sort(
        (a, b) =>
            (b.timestamp ?? DateTime(1)).compareTo(a.timestamp ?? DateTime(1)),
      );

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
    final weekStartDate = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );
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
      await _firestore
          .collection('user_streaks')
          .doc(userId)
          .set(<String, dynamic>{
            'user_id': userId,
            ...streak.toMap(),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
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
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

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
      final sessions = snapshot.docs
          .map((doc) => FocusSessionRecord.fromMap(doc.data()))
          .toList();

      if (sessions.isEmpty) {
        return 'user_id,subject,session_duration,focus_score,distraction_time,completed,timestamp\n';
      }

      final buffer = StringBuffer();
      buffer.writeln(
        'user_id,subject,session_duration,focus_score,distraction_time,completed,timestamp',
      );

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
      final encodedValue = value is String
          ? '"${value.replaceAll('"', '\\"')}"'
          : value;
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
