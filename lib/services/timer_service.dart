import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'insights_service.dart';

/// Timer execution state for a single block
enum TimerBlockState { pending, running, paused, completed, skipped }

/// Represents a block in execution with timing data
class ExecutingBlock {
  ExecutingBlock({
    required this.blockId,
    required this.subject,
    required this.durationSeconds,
    required this.type,
    required this.state,
    this.elapsedSeconds = 0,
    this.pausedAtSeconds = 0,
  });

  final String blockId;
  final String subject;
  final int durationSeconds;
  final PlanBlockType type;
  TimerBlockState state;
  int elapsedSeconds;
  int pausedAtSeconds; // When paused, store the elapsed time

  bool get isComplete => elapsedSeconds >= durationSeconds;
  int get remainingSeconds => durationSeconds - elapsedSeconds;
  double get progress => elapsedSeconds / durationSeconds;

  Map<String, dynamic> toMap() {
    return {
      'block_id': blockId,
      'subject': subject,
      'duration_seconds': durationSeconds,
      'type': type.name,
      'state': state.name,
      'elapsed_seconds': elapsedSeconds,
      'paused_at_seconds': pausedAtSeconds,
    };
  }

  factory ExecutingBlock.fromMap(Map<String, dynamic> data) {
    return ExecutingBlock(
      blockId: data['block_id'] as String,
      subject: data['subject'] as String,
      durationSeconds: data['duration_seconds'] as int,
      type: data['type'] == 'study'
          ? PlanBlockType.study
          : PlanBlockType.shortBreak,
      state: TimerBlockState.values.firstWhere(
        (s) => s.name == data['state'],
        orElse: () => TimerBlockState.pending,
      ),
      elapsedSeconds: data['elapsed_seconds'] as int? ?? 0,
      pausedAtSeconds: data['paused_at_seconds'] as int? ?? 0,
    );
  }
}

/// Queue state for multi-block timer execution
class TimerQueueState {
  TimerQueueState({
    required this.planId,
    required this.userId,
    required this.allBlocks,
    required this.currentBlockIndex,
    required this.startedAt,
    this.pausedAt,
    this.completedBlockCount = 0,
    this.skippedBlockCount = 0,
  });

  final String planId;
  final String userId;
  final List<ExecutingBlock> allBlocks;
  final int currentBlockIndex;
  final DateTime startedAt;
  DateTime? pausedAt;
  int completedBlockCount;
  int skippedBlockCount;

  /// Get current block
  ExecutingBlock? get currentBlock =>
      currentBlockIndex >= 0 && currentBlockIndex < allBlocks.length
      ? allBlocks[currentBlockIndex]
      : null;

  /// Get remaining blocks (not including current)
  List<ExecutingBlock> get upcomingBlocks =>
      allBlocks.sublist(currentBlockIndex + 1);

  /// Check if plan is complete
  bool get isComplete =>
      currentBlockIndex >= allBlocks.length ||
      (currentBlock?.state == TimerBlockState.completed &&
          upcomingBlocks.isEmpty);

  /// Get total plan duration in seconds
  int get totalPlanDurationSeconds =>
      allBlocks.fold<int>(0, (total, block) => total + block.durationSeconds);

  /// Get total elapsed across all blocks
  int get totalElapsedSeconds =>
      allBlocks.fold<int>(0, (total, block) => total + block.elapsedSeconds);

  /// Get overall progress
  double get overallProgress => totalPlanDurationSeconds > 0
      ? totalElapsedSeconds / totalPlanDurationSeconds
      : 0.0;

  Map<String, dynamic> toMap() {
    return {
      'plan_id': planId,
      'user_id': userId,
      'all_blocks': allBlocks.map((b) => b.toMap()).toList(),
      'current_block_index': currentBlockIndex,
      'started_at': startedAt.toIso8601String(),
      'paused_at': pausedAt?.toIso8601String(),
      'completed_block_count': completedBlockCount,
      'skipped_block_count': skippedBlockCount,
    };
  }

  factory TimerQueueState.fromMap(Map<String, dynamic> data) {
    final blocksList = data['all_blocks'] as List?;
    final blocks = blocksList != null
        ? blocksList
              .map<ExecutingBlock>(
                (b) => ExecutingBlock.fromMap(b as Map<String, dynamic>),
              )
              .toList()
        : <ExecutingBlock>[];

    return TimerQueueState(
      planId: data['plan_id'] as String,
      userId: data['user_id'] as String,
      allBlocks: blocks,
      currentBlockIndex: data['current_block_index'] as int? ?? 0,
      startedAt: DateTime.parse(data['started_at'] as String),
      pausedAt: data['paused_at'] != null
          ? DateTime.parse(data['paused_at'] as String)
          : null,
      completedBlockCount: data['completed_block_count'] as int? ?? 0,
      skippedBlockCount: data['skipped_block_count'] as int? ?? 0,
    );
  }
}

/// Multi-block timer service for synchronized execution
class TimerService {
  static final TimerService _instance = TimerService._internal();

  factory TimerService() {
    return _instance;
  }

  TimerService._internal();

  final InsightsService _insightsService = InsightsService();

  // State management
  TimerQueueState? _queueState;
  Timer? _executionTimer;
  DateTime? _timerStartTime;
  int _pausedElapsed = 0;
  bool _hasSavedResultsForCurrentPlan = false;
  DateTime? _lastQueuePersistAt;
  String? _lastPlanSyncSignature;

  // Event streams
  final _queueStateController = StreamController<TimerQueueState>.broadcast();
  final _blockCompleteController = StreamController<ExecutingBlock>.broadcast();
  final _planCompleteController = StreamController<String>.broadcast();

  /// Getters
  TimerQueueState? get queueState => _queueState;
  bool get isRunning => _executionTimer?.isActive ?? false;
  Stream<TimerQueueState> get queueStateStream => _queueStateController.stream;
  Stream<ExecutingBlock> get blockCompleteStream =>
      _blockCompleteController.stream;
  Stream<String> get planCompleteStream => _planCompleteController.stream;

  /// Initialize timer for a multi-block study plan
  Future<void> initializePlan(
    String planId,
    String userId,
    List<TrackedPlanBlock> trackedBlocks,
  ) async {
    final persistedState = await loadPersisted(userId, planId);
    if (persistedState != null && !persistedState.isComplete) {
      _queueState = persistedState;
      _hasSavedResultsForCurrentPlan = false;
      _lastQueuePersistAt = null;
      _lastPlanSyncSignature = null;
      _emitQueueState();
      return;
    }

    final orderedTrackedBlocks = [...trackedBlocks]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final executingBlocks = <ExecutingBlock>[];
    int blockId = 0;

    for (final block in orderedTrackedBlocks) {
      executingBlocks.add(
        ExecutingBlock(
          blockId: 'block_$blockId',
          subject: block.subject,
          durationSeconds: block.durationMinutes * 60,
          type: block.type,
          state: _toTimerState(block.status),
        ),
      );
      blockId++;
    }

    final firstPendingIndex = executingBlocks.indexWhere(
      (block) =>
          block.state != TimerBlockState.completed &&
          block.state != TimerBlockState.skipped,
    );

    _queueState = TimerQueueState(
      planId: planId,
      userId: userId,
      allBlocks: executingBlocks,
      currentBlockIndex: firstPendingIndex >= 0 ? firstPendingIndex : 0,
      startedAt: DateTime.now(),
    );
    _hasSavedResultsForCurrentPlan = false;
    _lastQueuePersistAt = null;
    _lastPlanSyncSignature = null;

    _normalizeSingleActiveBlock();

    _emitQueueState();
    await _persistQueueState();
  }

  /// Start timer execution
  void startTimer() {
    if (_queueState == null || isRunning) return;

    final current = _queueState!.currentBlock;
    if (current == null) {
      _notifyPlanComplete();
      return;
    }

    current.state = TimerBlockState.running;
    _normalizeSingleActiveBlock();
    _timerStartTime = DateTime.now();
    _pausedElapsed = current.elapsedSeconds;

    _executionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimerTick();
    });

    _emitQueueState();
  }

  /// Pause timer
  void pauseTimer() {
    if (_queueState == null || !isRunning) return;

    _executionTimer?.cancel();
    _executionTimer = null;

    final current = _queueState!.currentBlock;
    if (current != null) {
      current.state = TimerBlockState.paused;
      current.pausedAtSeconds = current.elapsedSeconds;
      _queueState!.pausedAt = DateTime.now();
    }

    _normalizeSingleActiveBlock();

    _emitQueueState();
  }

  /// Resume timer from pause
  void resumeTimer() {
    if (_queueState == null) return;

    final current = _queueState!.currentBlock;
    if (current?.state != TimerBlockState.paused) return;

    current!.state = TimerBlockState.running;
    _normalizeSingleActiveBlock();
    _timerStartTime = DateTime.now();
    _pausedElapsed = current.elapsedSeconds;
    _queueState!.pausedAt = null;

    _executionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimerTick();
    });

    _emitQueueState();
  }

  /// Skip current block
  void skipBlock() {
    if (_queueState == null) return;

    final current = _queueState!.currentBlock;
    if (current != null) {
      current.state = TimerBlockState.skipped;
      _queueState!.skippedBlockCount++;
    }

    _normalizeSingleActiveBlock();

    _moveToNextBlock();
  }

  /// Complete current block manually
  void completeBlock() {
    if (_queueState == null) return;

    final current = _queueState!.currentBlock;
    if (current != null) {
      current.elapsedSeconds = current.durationSeconds;
      current.state = TimerBlockState.completed;
      _queueState!.completedBlockCount++;
      _blockCompleteController.add(current);
    }

    _normalizeSingleActiveBlock();

    _moveToNextBlock();
  }

  /// End plan early by skipping current and remaining blocks.
  Future<void> endPlanEarly() async {
    if (_queueState == null) return;

    _executionTimer?.cancel();
    _executionTimer = null;
    _timerStartTime = null;
    _pausedElapsed = 0;

    final blocks = _queueState!.allBlocks;
    var completedCount = 0;
    var skippedCount = 0;

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (i >= _queueState!.currentBlockIndex &&
          block.state != TimerBlockState.completed &&
          block.state != TimerBlockState.skipped) {
        block.state = TimerBlockState.skipped;
      }

      if (block.state == TimerBlockState.completed) {
        completedCount++;
      } else if (block.state == TimerBlockState.skipped) {
        skippedCount++;
      }
    }

    _queueState = TimerQueueState(
      planId: _queueState!.planId,
      userId: _queueState!.userId,
      allBlocks: blocks,
      currentBlockIndex: blocks.length,
      startedAt: _queueState!.startedAt,
      pausedAt: DateTime.now(),
      completedBlockCount: completedCount,
      skippedBlockCount: skippedCount,
    );

    _normalizeSingleActiveBlock();
    _emitQueueState();
    _notifyPlanComplete();
  }

  /// Stop timer completely
  void stopTimer() {
    _executionTimer?.cancel();
    _executionTimer = null;
    _timerStartTime = null;
    _pausedElapsed = 0;

    if (_queueState?.currentBlock != null) {
      _queueState!.currentBlock!.state = TimerBlockState.paused;
    }

    _normalizeSingleActiveBlock();

    _emitQueueState();
  }

  /// Dispose resources
  void dispose() {
    stopTimer();
  }

  /// Reset for new plan
  void reset() {
    dispose();
    _queueState = null;
    _executionTimer = null;
    _timerStartTime = null;
    _pausedElapsed = 0;
  }

  // Private methods

  void _updateTimerTick() {
    if (_queueState == null || _timerStartTime == null) return;

    final current = _queueState!.currentBlock;
    if (current == null) return;

    final elapsed = DateTime.now().difference(_timerStartTime!).inSeconds;
    current.elapsedSeconds = _pausedElapsed + elapsed;

    // Check if block is complete
    if (current.isComplete) {
      current.state = TimerBlockState.completed;
      _queueState!.completedBlockCount++;
      _blockCompleteController.add(current);

      _executionTimer?.cancel();
      _executionTimer = null;

      // Auto-move to next block
      Future.delayed(const Duration(milliseconds: 500), _moveToNextBlock);
    }

    _normalizeSingleActiveBlock();

    _emitQueueState();
  }

  void _moveToNextBlock() {
    if (_queueState == null) return;

    if (_timerStartTime != null) _queueState!.pausedAt = DateTime.now();

    _executionTimer?.cancel();
    _executionTimer = null;
    _timerStartTime = null;
    _pausedElapsed = 0;

    if (_queueState!.currentBlockIndex < _queueState!.allBlocks.length - 1) {
      _queueState = TimerQueueState(
        planId: _queueState!.planId,
        userId: _queueState!.userId,
        allBlocks: _queueState!.allBlocks,
        currentBlockIndex: _queueState!.currentBlockIndex + 1,
        startedAt: _queueState!.startedAt,
        pausedAt: _queueState!.pausedAt,
        completedBlockCount: _queueState!.completedBlockCount,
        skippedBlockCount: _queueState!.skippedBlockCount,
      );
      final nextBlock = _queueState!.currentBlock;

      if (nextBlock != null) {
        nextBlock.state = TimerBlockState.pending;
      }

      _normalizeSingleActiveBlock();

      // Automatic progression for both study and break blocks.
      Future.delayed(const Duration(milliseconds: 400), startTimer);
    } else {
      // Plan is complete
      _notifyPlanComplete();
    }

    _emitQueueState();
  }

  void _notifyPlanComplete() {
    _executionTimer?.cancel();
    if (_queueState != null) {
      unawaited(saveSessionResults(_queueState!.userId));
      unawaited(
        _insightsService.syncPlanSchedule(
          planId: _queueState!.planId,
          blocks: _toTrackedBlocks(_queueState!.allBlocks),
          currentBlockIndex: _queueState!.allBlocks.length,
          planStatus: 'completed',
        ),
      );
      _planCompleteController.add(_queueState!.planId);
    }
  }

  void _emitQueueState() {
    if (_queueState != null) {
      _normalizeSingleActiveBlock();
      _queueStateController.add(_queueState!);

      final now = DateTime.now();
      final shouldPersistQueue =
          _lastQueuePersistAt == null ||
          now.difference(_lastQueuePersistAt!).inSeconds >= 5 ||
          !isRunning;

      if (shouldPersistQueue) {
        _lastQueuePersistAt = now;
        unawaited(_persistQueueState());
      }

      final trackedBlocks = _toTrackedBlocks(_queueState!.allBlocks);
      final signature = [
        _queueState!.planId,
        _queueState!.currentBlockIndex,
        _queueState!.completedBlockCount,
        _queueState!.skippedBlockCount,
        trackedBlocks.map((b) => b.status.name).join(','),
      ].join('|');

      if (_lastPlanSyncSignature != signature) {
        _lastPlanSyncSignature = signature;
        unawaited(
          _insightsService.syncPlanSchedule(
            planId: _queueState!.planId,
            blocks: trackedBlocks,
            currentBlockIndex: _queueState!.currentBlockIndex,
            planStatus: _queueState!.isComplete ? 'completed' : 'active',
          ),
        );
      }
    }
  }

  List<TrackedPlanBlock> _toTrackedBlocks(List<ExecutingBlock> blocks) {
    return blocks
        .asMap()
        .entries
        .map(
          (entry) => TrackedPlanBlock(
            subject: entry.value.subject,
            durationMinutes: (entry.value.durationSeconds / 60).round(),
            status: _toPlanStatus(entry.value.state),
            type: entry.value.type,
            orderIndex: entry.key,
          ),
        )
        .toList();
  }

  PlanBlockStatus _toPlanStatus(TimerBlockState state) {
    switch (state) {
      case TimerBlockState.running:
      case TimerBlockState.paused:
        return PlanBlockStatus.active;
      case TimerBlockState.completed:
        return PlanBlockStatus.completed;
      case TimerBlockState.skipped:
        return PlanBlockStatus.skipped;
      case TimerBlockState.pending:
        return PlanBlockStatus.pending;
    }
  }

  TimerBlockState _toTimerState(PlanBlockStatus status) {
    switch (status) {
      case PlanBlockStatus.active:
        return TimerBlockState.paused;
      case PlanBlockStatus.completed:
        return TimerBlockState.completed;
      case PlanBlockStatus.skipped:
        return TimerBlockState.skipped;
      case PlanBlockStatus.pending:
        return TimerBlockState.pending;
    }
  }

  void _normalizeSingleActiveBlock() {
    if (_queueState == null) {
      return;
    }

    for (var i = 0; i < _queueState!.allBlocks.length; i++) {
      final block = _queueState!.allBlocks[i];
      if (i < _queueState!.currentBlockIndex &&
          block.state != TimerBlockState.completed &&
          block.state != TimerBlockState.skipped) {
        block.state = TimerBlockState.completed;
      }

      if (i > _queueState!.currentBlockIndex &&
          block.state != TimerBlockState.completed &&
          block.state != TimerBlockState.skipped) {
        block.state = TimerBlockState.pending;
      }
    }

    final current = _queueState!.currentBlock;
    if (current != null &&
        current.state != TimerBlockState.running &&
        current.state != TimerBlockState.paused &&
        current.state != TimerBlockState.completed &&
        current.state != TimerBlockState.skipped) {
      current.state = TimerBlockState.pending;
    }
  }

  Future<void> _persistQueueState() async {
    if (_queueState == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_queueState!.userId)
          .collection('timer_queue_state')
          .doc(_queueState!.planId)
          .set(_queueState!.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error persisting timer queue state: $e');
    }
  }

  /// Load persisted queue state
  static Future<TimerQueueState?> loadPersisted(
    String userId,
    String planId,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('timer_queue_state')
          .doc(planId)
          .get();

      if (doc.exists) {
        return TimerQueueState.fromMap(doc.data() ?? {});
      }
    } catch (e) {
      debugPrint('Error loading timer queue state: $e');
    }
    return null;
  }

  /// Save session results to firestore
  Future<void> saveSessionResults(String userId) async {
    if (_queueState == null) return;
    if (_hasSavedResultsForCurrentPlan) return;

    try {
      final now = DateTime.now();
      final totalDuration = now.difference(_queueState!.startedAt);

      final studyBlocks = _queueState!.allBlocks
          .where((block) => block.type == PlanBlockType.study)
          .toList();
      final totalStudySeconds = studyBlocks.fold<int>(
        0,
        (total, block) => total + block.durationSeconds,
      );
      final completedStudySeconds = studyBlocks.fold<int>(
        0,
        (total, block) =>
            total + block.elapsedSeconds.clamp(0, block.durationSeconds),
      );

      final focusScore = totalStudySeconds <= 0
          ? 0.0
          : ((completedStudySeconds / totalStudySeconds) * 100)
                .clamp(0, 100)
                .toDouble();

      final subject = studyBlocks.isEmpty
          ? 'Smart Session'
          : studyBlocks
                .map((block) => block.subject.trim())
                .firstWhere(
                  (name) => name.isNotEmpty,
                  orElse: () => 'Smart Session',
                );

      final isCompleted =
          _queueState!.completedBlockCount >= _queueState!.allBlocks.length &&
          _queueState!.skippedBlockCount == 0;

      await _insightsService.saveSessionRecord(
        SessionRecordInput(
          userId: userId,
          sessionDurationSeconds: totalDuration.inSeconds,
          focusScore: focusScore,
          timestamp: now,
          subject: subject,
          completed: isCompleted,
          planId: _queueState!.planId,
        ),
      );

      _hasSavedResultsForCurrentPlan = true;
    } catch (e) {
      debugPrint('Error saving session results: $e');
    }
  }
}
