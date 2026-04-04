import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../core/theme.dart';
import '../services/insights_service.dart';
import '../services/timer_service.dart';
import 'widgets/modern_components.dart';

class _FocusStream {
  const _FocusStream({required this.name, required this.urls});

  final String name;
  final List<String> urls;
}

class MultiBlockTimerScreen extends StatefulWidget {
  const MultiBlockTimerScreen({
    super.key,
    required this.plan,
    this.autostartBlocks = false,
  });

  final TrackedStudyPlan plan;
  final bool autostartBlocks;

  @override
  State<MultiBlockTimerScreen> createState() => _MultiBlockTimerScreenState();
}

class _MultiBlockTimerScreenState extends State<MultiBlockTimerScreen>
    with WidgetsBindingObserver {
  static const List<_FocusStream> _streams = [
    _FocusStream(
      name: 'Rain / Nature',
      urls: [
        'https://radio.stereoscenic.com/relaxingrain.mp3',
        'https://radio.stereoscenic.com/relaxingrain.ogg',
      ],
    ),
    _FocusStream(
      name: 'Ambient / Deep Focus',
      urls: [
        'https://ice1.somafm.com/dronezone-128-mp3',
        'https://ice2.somafm.com/dronezone-128-mp3',
      ],
    ),
  ];

  late TimerService _timerService;
  late AudioPlayer _audioPlayer;
  late StreamSubscription<TimerQueueState> _queueSubscription;
  late StreamSubscription<ExecutingBlock> _blockCompleteSubscription;
  late StreamSubscription<String> _planCompleteSubscription;

  TimerQueueState? _queueState;
  bool _isAudioPlaying = false;
  int _currentStreamIndex = 0;
  bool _isSwitchingStream = false;
  DateTime? _backgroundedAt;
  bool _endingPlanEarly = false;

  _FocusStream get _currentStream => _streams[_currentStreamIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _timerService = TimerService();
    _audioPlayer = AudioPlayer();

    _initializeTimer();
    _setupListeners();
  }

  void _initializeTimer() async {
    try {
      // Initialize the timer service with tracked blocks
      await _timerService.initializePlan(
        widget.plan.id,
        widget.plan.userId,
        widget.plan.blocks,
      );

      if (mounted) {
        setState(() {
          _queueState = _timerService.queueState;
        });
      }
    } catch (e) {
      debugPrint('Error initializing timer: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error initializing timer: $e')));
      }
    }
  }

  void _setupListeners() {
    _queueSubscription = _timerService.queueStateStream.listen((queueState) {
      if (mounted) {
        setState(() {
          _queueState = queueState;
        });
      }
    });

    _blockCompleteSubscription = _timerService.blockCompleteStream.listen((
      block,
    ) {
      _showBlockComplete(block);
    });

    _planCompleteSubscription = _timerService.planCompleteStream.listen((_) {
      if (_endingPlanEarly) {
        return;
      }
      _showPlanComplete();
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = state.playing;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      if (_timerService.isRunning) {
        _timerService.pauseTimer();
      }
      return;
    }

    if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      _backgroundedAt = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _queueSubscription.cancel();
    _blockCompleteSubscription.cancel();
    _planCompleteSubscription.cancel();
    _audioPlayer.dispose();
    _timerService.dispose();
    super.dispose();
  }

  void _playCurrentStream() async {
    try {
      for (final url in _currentStream.urls) {
        try {
          await _audioPlayer.setUrl(url);
          await _audioPlayer.play();
          return;
        } catch (e) {
          debugPrint('Failed to play $url: $e');
          continue;
        }
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  void _toggleAudio() {
    if (_isAudioPlaying) {
      _audioPlayer.pause();
    } else {
      _playCurrentStream();
    }
  }

  void _switchStream() async {
    if (_isSwitchingStream) return;

    setState(() => _isSwitchingStream = true);

    try {
      await _audioPlayer.stop();
      setState(
        () => _currentStreamIndex = (_currentStreamIndex + 1) % _streams.length,
      );
      await Future.delayed(const Duration(milliseconds: 200));
      _playCurrentStream();
    } finally {
      if (mounted) {
        setState(() => _isSwitchingStream = false);
      }
    }
  }

  void _startTimer() {
    _timerService.startTimer();
    if (widget.autostartBlocks && !_isAudioPlaying) {
      _playCurrentStream();
    }
  }

  void _pauseTimer() {
    _timerService.pauseTimer();
    _audioPlayer.pause();
  }

  void _resumeTimer() {
    _timerService.resumeTimer();
    if (widget.autostartBlocks && !_isAudioPlaying) {
      _playCurrentStream();
    }
  }

  void _skipBlock() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          'Skip Block?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Text(
          'Are you sure you want to skip this block?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _timerService.skipBlock();
              Navigator.pop(ctx);
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  void _finishSession() async {
    _timerService.pauseTimer();
    _audioPlayer.stop();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _timerService.saveSessionResults(user.uid);
      }
    } catch (e) {
      debugPrint('Error saving session: $e');
    }

    if (mounted) {
      Navigator.of(context).pop(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Study session saved! ${_queueState?.completedBlockCount ?? 0}/${_queueState?.allBlocks.length ?? 0} blocks completed.',
            ),
          ),
        );
      }
    }
  }

  void _showBlockComplete(ExecutingBlock block) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${block.subject} completed.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.statusSuccess,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showPlanComplete() {
    _audioPlayer.stop();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          'Study Plan Complete',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Completed: ${_queueState?.completedBlockCount}/${_queueState?.allBlocks.length}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.md),
            Text(
              'Total time: ${_formatDuration(Duration(seconds: _queueState?.totalElapsedSeconds ?? 0))}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: _finishSession, child: const Text('Finish')),
        ],
      ),
    );
  }

  Future<void> _confirmEndPlan() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('End Plan', style: Theme.of(context).textTheme.titleLarge),
        content: Text(
          'Are you sure you want to end this plan? Remaining blocks will be marked as skipped.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Plan'),
          ),
        ],
      ),
    );

    if (shouldEnd != true) {
      return;
    }

    _endingPlanEarly = true;
    _audioPlayer.stop();
    await _timerService.endPlanEarly();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _timerService.saveSessionResults(user.uid);
      }
    } catch (e) {
      debugPrint('Error saving ended-plan session: $e');
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plan ended early. Remaining blocks skipped.'),
        ),
      );
    }
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    if (_queueState == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgDeepDark,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final current = _queueState!.currentBlock;
    final nextUpcoming = _queueState!.upcomingBlocks.isNotEmpty
        ? _queueState!.upcomingBlocks.first
        : null;
    final remaining = current?.remainingSeconds ?? 0;
    final duration = current?.durationSeconds ?? 1;
    final progress = current != null ? current.progress : 0.0;
    final isRunning = current?.state == TimerBlockState.running;
    final isPaused = current?.state == TimerBlockState.paused;

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.lg,
                  AppTheme.lg,
                  AppTheme.lg,
                  150,
                ),
                child: Column(
                  children: [
                    // Header with back button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        Text(
                          'Study Plan',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextButton(
                          onPressed: _confirmEndPlan,
                          child: const Text('End Plan'),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppTheme.xl),

                    // Overall progress
                    ModernProgressBar(
                      progress: _queueState!.overallProgress,
                      label: 'Overall Progress',
                      progressColor: AppTheme.accentSecondary,
                    ),

                    const SizedBox(height: 12),
                    ModernCard(
                      child: Column(
                        children: [
                          if (current != null)
                            _SessionSummaryRow(
                              title: 'Current Session',
                              subject: current.subject,
                              durationMinutes: current.durationSeconds ~/ 60,
                              label: 'Active',
                              labelColor: AppTheme.accentSecondary,
                            ),
                          if (current != null && nextUpcoming != null)
                            const SizedBox(height: 10),
                          if (nextUpcoming != null)
                            _SessionSummaryRow(
                              title: 'Next Session',
                              subject: nextUpcoming.subject,
                              durationMinutes:
                                  nextUpcoming.durationSeconds ~/ 60,
                              label: 'Up Next',
                              labelColor: AppTheme.textSecondary,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppTheme.xl),

                    // Current block display
                    if (current != null) ...[
                      Text(
                        current.subject,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentPrimary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.md),
                      Text(
                        current.type == PlanBlockType.study ? 'Study' : 'Break',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Active',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.accentSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppTheme.xl),

                      // Timer circle
                      _buildTimerCircle(remaining, duration, progress),

                      const SizedBox(height: AppTheme.xl),

                      // Control buttons row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!isRunning && !isPaused)
                            _buildControlButton(
                              icon: Icons.play_arrow_rounded,
                              label: 'Start Session',
                              onTap: _startTimer,
                            )
                          else if (isRunning)
                            _buildControlButton(
                              icon: Icons.pause_rounded,
                              label: 'Pause',
                              onTap: _pauseTimer,
                            )
                          else
                            _buildControlButton(
                              icon: Icons.play_arrow_rounded,
                              label: 'Continue Plan',
                              onTap: _resumeTimer,
                            ),
                          const SizedBox(width: AppTheme.lg),
                          _buildControlButton(
                            icon: Icons.skip_next_rounded,
                            label: 'Skip',
                            onTap: _skipBlock,
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: AppTheme.xxl),

                    // Queue section
                    if (_queueState!.upcomingBlocks.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Upcoming Blocks',
                        subtitle:
                            '${_queueState!.upcomingBlocks.length} remaining',
                      ),
                      const SizedBox(height: AppTheme.lg),
                      ..._queueState!.upcomingBlocks.asMap().entries.map(
                        (entry) => _buildQueueBlockTile(
                          entry.key,
                          entry.value,
                          statusLabel: entry.key == 0 ? 'Up Next' : 'Upcoming',
                        ),
                      ),
                    ],

                    const SizedBox(height: AppTheme.xl),

                    // Completed blocks summary
                    if (_queueState!.completedBlockCount > 0)
                      ModernCard(
                        backgroundColor: AppTheme.statusSuccess.withValues(
                          alpha: 0.1,
                        ),
                        borderColor: AppTheme.statusSuccess.withValues(
                          alpha: 0.3,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: AppTheme.statusSuccess,
                              size: 28,
                            ),
                            const SizedBox(width: AppTheme.lg),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Completed',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.textSecondary),
                                ),
                                Text(
                                  '${_queueState!.completedBlockCount} / ${_queueState!.allBlocks.length} blocks',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.statusSuccess,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Audio controls bottom card
              Positioned(
                left: AppTheme.lg,
                right: AppTheme.lg,
                bottom: AppTheme.lg,
                child: _buildAudioCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerCircle(int remaining, int duration, double progress) {
    return CircularPercentIndicator(
      radius: 120,
      lineWidth: 12,
      animation: false,
      percent: progress.clamp(0.0, 1.0),
      backgroundColor: AppTheme.bgCard,
      progressColor: AppTheme.accentSecondary,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(remaining),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.md),
          Text(
            'of ${_formatTime(duration)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.xl,
            vertical: AppTheme.lg,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            color: AppTheme.bgCard,
            border: Border.all(color: AppTheme.bgCardLight, width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.accentSecondary, size: 28),
              const SizedBox(height: AppTheme.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueBlockTile(
    int index,
    ExecutingBlock block, {
    required String statusLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.md),
      child: ModernCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentSecondary.withValues(alpha: 0.1),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.subject,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.xs),
                  Row(
                    children: [
                      Icon(
                        block.type == PlanBlockType.study
                            ? Icons.menu_book_rounded
                            : Icons.coffee_rounded,
                        size: 14,
                        color: AppTheme.textTertiary,
                      ),
                      const SizedBox(width: AppTheme.xs),
                      Text(
                        block.type == PlanBlockType.study ? 'Study' : 'Break',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppTheme.lg),
                      Text(
                        '${block.durationSeconds ~/ 60} min',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppTheme.lg),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: AppTheme.bgCardLight,
                        ),
                        child: Text(
                          statusLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: statusLabel == 'Up Next'
                                    ? AppTheme.accentSecondary
                                    : AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCard() {
    return ModernCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Now: ${_currentStream.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppTheme.md),
          _buildMiniButton(
            icon: _isAudioPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            onTap: _toggleAudio,
          ),
          const SizedBox(width: AppTheme.md),
          _buildMiniButton(
            icon: _isSwitchingStream
                ? Icons.hourglass_bottom_rounded
                : Icons.swap_horiz_rounded,
            onTap: _isSwitchingStream ? null : _switchStream,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            color: AppTheme.bgCardLight,
          ),
          child: Icon(icon, size: 20, color: AppTheme.accentSecondary),
        ),
      ),
    );
  }
}

class _SessionSummaryRow extends StatelessWidget {
  const _SessionSummaryRow({
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$subject · $durationMinutes min',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: AppTheme.bgCardLight,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
