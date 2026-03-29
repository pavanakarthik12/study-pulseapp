import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:just_audio/just_audio.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import 'widgets/ui_shell.dart';

class _FocusStream {
  const _FocusStream({required this.name, required this.urls});

  final String name;
  final List<String> urls;
}

class StudyTimerScreen extends StatefulWidget {
  const StudyTimerScreen({super.key});

  @override
  State<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends State<StudyTimerScreen>
  with WidgetsBindingObserver {
  static const int _defaultSeconds = 25 * 60;
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

  Timer? _timer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _subjectController = TextEditingController();
  int _remainingSeconds = _defaultSeconds;
  int _currentStreamIndex = 0;
  bool _isRunning = false;
  bool _isAudioPlaying = false;
  bool _isSwitchingStream = false;
  bool _hasSessionStarted = false;
  bool _isSavingSession = false;
  DateTime? _sessionStartedAt;
  DateTime? _backgroundedAt;
  Duration _distractionDuration = Duration.zero;
  StreamSubscription<PlayerState>? _playerStateSub;

  _FocusStream get _currentStream => _streams[_currentStreamIndex];

  String get _nowPlayingLabel => 'Now Playing: ${_currentStream.name}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }

      if (state.processingState == ProcessingState.completed) {
        _audioPlayer.play();
      }

      setState(() {
        _isAudioPlaying = state.playing;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _playerStateSub?.cancel();
    _subjectController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_hasSessionStarted || _remainingSeconds == 0) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      _distractionDuration += DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
    }
  }

  Future<void> _start() async {
    if (_isRunning) {
      return;
    }

    _sessionStartedAt ??= DateTime.now();
    _hasSessionStarted = true;

    setState(() {
      _isRunning = true;
    });

    await _playCurrentStream();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _isRunning = false;
        });
        _audioPlayer.pause();
        unawaited(_finishSession());
        return;
      }

      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
    });
    _audioPlayer.pause();
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _defaultSeconds;
    });
    _audioPlayer.pause();
    _audioPlayer.seek(Duration.zero);
    _resetSessionTracking();
  }

  Future<void> _finishSession() async {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) {
      return;
    }

    if (_backgroundedAt != null) {
      _distractionDuration += DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
    }

    final totalSeconds = math.max(
      DateTime.now().difference(startedAt).inSeconds,
      1,
    );
    final distractionSeconds = math.max(_distractionDuration.inSeconds, 0);
    final focusedSeconds = math.max(totalSeconds - distractionSeconds, 0);
    final focusScore = (focusedSeconds / totalSeconds) * 100;

    await _saveSessionToFirestore(
      sessionDurationSeconds: totalSeconds,
      focusScore: focusScore,
      distractionSeconds: distractionSeconds,
      subject: _normalizedSubject,
    );

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _FocusScoreDialog(
          focusScore: focusScore,
          focusedSeconds: focusedSeconds,
          totalSeconds: totalSeconds,
        );
      },
    );

    _resetSessionTracking();
    if (mounted) {
      setState(() {
        _remainingSeconds = _defaultSeconds;
      });
    }
  }

  Future<void> _saveSessionToFirestore({
    required int sessionDurationSeconds,
    required int distractionSeconds,
    required double focusScore,
    String? subject,
  }) async {
    if (_isSavingSession) {
      return;
    }

    _isSavingSession = true;
    try {
      final payload = <String, dynamic>{
        'session_duration': sessionDurationSeconds,
        'focus_score': focusScore,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (subject != null && subject.isNotEmpty) {
        payload['subject'] = subject;
      }

      // Extra behavioral signal for future ML features.
      payload['distraction_duration'] = distractionSeconds;

      await _firestore.collection('focus_sessions').add(payload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session saved locally in app state only.'),
          ),
        );
      }
    } finally {
      _isSavingSession = false;
    }
  }

  void _resetSessionTracking() {
    _hasSessionStarted = false;
    _sessionStartedAt = null;
    _backgroundedAt = null;
    _distractionDuration = Duration.zero;
  }

  String? get _normalizedSubject {
    final value = _subjectController.text.trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> _playCurrentStream() async {
    String? lastFailedUrl;
    for (final url in _currentStream.urls) {
      try {
        final currentUrl = _audioPlayer.audioSource is UriAudioSource
            ? (_audioPlayer.audioSource as UriAudioSource).uri.toString()
            : null;

        if (currentUrl != url) {
          await _audioPlayer.setUrl(url);
        }
        await _audioPlayer.play();
        return;
      } catch (_) {
        lastFailedUrl = url;
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lastFailedUrl == null
              ? 'Could not play stream right now.'
              : 'Could not connect to stream. Please try again.',
        ),
      ),
    );
  }

  Future<void> _toggleAudio() async {
    if (_isAudioPlaying) {
      await _audioPlayer.pause();
      return;
    }
    await _playCurrentStream();
  }

  Future<void> _switchStream() async {
    setState(() {
      _isSwitchingStream = true;
      _currentStreamIndex = (_currentStreamIndex + 1) % _streams.length;
    });

    try {
      await _playCurrentStream();
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingStream = false;
        });
      }
    }
  }

  String get _timeText {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double get _progress {
    final raw = _remainingSeconds / _defaultSeconds;
    return raw.clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = _remainingSeconds == 0;
    final isFresh = _remainingSeconds == _defaultSeconds;

    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 170),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                      ),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF7C9BFF).withValues(alpha: 0.35),
                            blurRadius: 42,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: CircularPercentIndicator(
                        radius: 140,
                        lineWidth: 14,
                        animation: true,
                        animateFromLastPercent: true,
                        animationDuration: 900,
                        circularStrokeCap: CircularStrokeCap.round,
                        percent: _progress,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        progressColor: const Color(0xFF7C9BFF),
                        center: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeText,
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isFinished ? 'Session complete' : 'Focus timer',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .fade(duration: 500.ms)
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          duration: 500.ms,
                        ),
                    const SizedBox(height: 40),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: TextField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          hintText: 'Subject (optional)',
                          prefixIcon: Icon(Icons.menu_book_rounded),
                        ),
                      ),
                    )
                        .animate(delay: 80.ms)
                        .fade(duration: 420.ms)
                        .slideY(begin: 0.12, end: 0, duration: 420.ms),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isRunning)
                          _TimerActionButton(
                            icon: Icons.pause_rounded,
                            label: 'Pause',
                            onTap: _pause,
                          )
                        else
                          _TimerActionButton(
                            icon: Icons.play_arrow_rounded,
                            label: isFresh ? 'Start' : 'Resume',
                            onTap: _start,
                          ),
                        const SizedBox(width: 14),
                        _TimerActionButton(
                          icon: Icons.stop_rounded,
                          label: 'Stop',
                          onTap: _stop,
                        ),
                      ],
                    )
                        .animate(delay: 120.ms)
                        .fade(duration: 500.ms)
                        .slideY(begin: 0.15, end: 0, duration: 500.ms),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: _FocusRadioCard(
                  nowPlaying: _nowPlayingLabel,
                  isPlaying: _isAudioPlaying,
                  isSwitching: _isSwitchingStream,
                  onTogglePlay: _toggleAudio,
                  onSwitchStream: _switchStream,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusRadioCard extends StatelessWidget {
  const _FocusRadioCard({
    required this.nowPlaying,
    required this.isPlaying,
    required this.isSwitching,
    required this.onTogglePlay,
    required this.onSwitchStream,
  });

  final String nowPlaying;
  final bool isPlaying;
  final bool isSwitching;
  final VoidCallback onTogglePlay;
  final VoidCallback onSwitchStream;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.24),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF57D2FF)
                    .withValues(alpha: isPlaying ? 0.28 : 0.08),
                blurRadius: isPlaying ? 24 : 8,
                spreadRadius: isPlaying ? 2 : 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    nowPlaying,
                    key: ValueKey<String>(nowPlaying),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _MiniActionButton(
                icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: onTogglePlay,
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: isSwitching
                    ? Container(
                        key: const ValueKey<String>('switching'),
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white.withValues(alpha: 0.12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _MiniActionButton(
                        key: const ValueKey<String>('switch'),
                        icon: Icons.swap_horiz_rounded,
                        onTap: onSwitchStream,
                      ),
              ),
            ],
          ),
        )
            .animate(target: isPlaying ? 1 : 0)
            .scale(
              begin: const Offset(0.99, 0.99),
              end: const Offset(1.0, 1.0),
              duration: 260.ms,
            ),
      ),
    );
  }
}

class _MiniActionButton extends StatefulWidget {
  const _MiniActionButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_MiniActionButton> createState() => _MiniActionButtonState();
}

class _MiniActionButtonState extends State<_MiniActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: _pressed ? 0.9 : 1,
        child: Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(widget.icon, size: 22),
        ),
      ),
    );
  }
}

class _TimerActionButton extends StatefulWidget {
  const _TimerActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_TimerActionButton> createState() => _TimerActionButtonState();
}

class _TimerActionButtonState extends State<_TimerActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: _pressed ? 0.94 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.1),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20),
              const SizedBox(width: 8),
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusScoreDialog extends StatelessWidget {
  const _FocusScoreDialog({
    required this.focusScore,
    required this.focusedSeconds,
    required this.totalSeconds,
  });

  final double focusScore;
  final int focusedSeconds;
  final int totalSeconds;

  Color get _scoreColor {
    if (focusScore >= 75) {
      return const Color(0xFF4BD37B);
    }
    if (focusScore >= 45) {
      return const Color(0xFFF2C94C);
    }
    return const Color(0xFFFF6B6B);
  }

  String get _message {
    if (focusScore >= 85) {
      return 'Excellent focus. Keep this rhythm going.';
    }
    if (focusScore >= 65) {
      return 'Strong session. Small gains will push you higher.';
    }
    if (focusScore >= 45) {
      return 'Decent effort. Try reducing interruptions next round.';
    }
    return 'You showed up. Reset and come back stronger.';
  }

  @override
  Widget build(BuildContext context) {
    final percent = (focusScore / 100).clamp(0.0, 1.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Focus Score',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 18),
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(begin: 0, end: percent),
                  builder: (context, value, _) {
                    return CircularPercentIndicator(
                      radius: 92,
                      lineWidth: 13,
                      percent: value,
                      animation: false,
                      circularStrokeCap: CircularStrokeCap.round,
                      progressColor: _scoreColor,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      center: Text(
                        '${(value * 100).round()}%\nFocus',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: _scoreColor,
                                ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Focused $focusedSeconds sec out of $totalSeconds sec',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.62),
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