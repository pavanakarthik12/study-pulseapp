import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../core/theme.dart';
import 'widgets/modern_components.dart';

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
      sessionStartedAt: startedAt,
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
    required DateTime sessionStartedAt,
    String? subject,
  }) async {
    if (_isSavingSession) {
      return;
    }

    _isSavingSession = true;
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null || userId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please login to save sessions.')),
          );
        }
        return;
      }

      final payload = <String, dynamic>{
        'user_id': userId,
        'subject': subject ?? 'General Focus',
        'session_duration': sessionDurationSeconds,
        'focus_score': focusScore,
        'distraction_time': distractionSeconds,
        'completed': true,
        'timestamp': FieldValue.serverTimestamp(),
        'session_started_at': Timestamp.fromDate(sessionStartedAt),
      };

      await _firestore.collection('focus_sessions').add(payload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save session. Please try again.'),
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
      body: GradientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.lg,
                  AppTheme.lg,
                  AppTheme.lg,
                  170,
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Back',
                      ),
                    ),
                    const Spacer(),
                    _buildTimerDisplay(context, isFinished),
                    const SizedBox(height: AppTheme.xl),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: ModernTextField(
                        controller: _subjectController,
                        label: 'Study Subject',
                        hint: 'What are you focusing on?',
                        prefixIcon: Icons.menu_book_rounded,
                      ),
                    ),
                    const SizedBox(height: AppTheme.xl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isRunning)
                          _buildTimerButton(
                            icon: Icons.pause_rounded,
                            label: 'Pause',
                            onTap: _pause,
                          )
                        else
                          _buildTimerButton(
                            icon: Icons.play_arrow_rounded,
                            label: isFresh ? 'Start Session' : 'Continue Plan',
                            onTap: _start,
                          ),
                        const SizedBox(width: AppTheme.lg),
                        _buildTimerButton(
                          icon: Icons.stop_rounded,
                          label: 'Stop',
                          onTap: _stop,
                        ),
                      ],
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
              Positioned(
                left: AppTheme.lg,
                right: AppTheme.lg,
                bottom: AppTheme.lg,
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

  Widget _buildTimerDisplay(BuildContext context, bool isFinished) {
    return CircularPercentIndicator(
      radius: 120,
      lineWidth: 12,
      animation: true,
      animateFromLastPercent: true,
      animationDuration: 900,
      circularStrokeCap: CircularStrokeCap.round,
      percent: _progress,
      backgroundColor: AppTheme.bgCard,
      progressColor: AppTheme.accentSecondary,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _timeText,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.md),
          Text(
            isFinished ? 'Complete' : 'Focus time',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerButton({
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: AppTheme.md,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        color: AppTheme.bgCard,
        border: Border.all(color: AppTheme.bgCardLight, width: 1),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.md),
          _MiniActionButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onTap: onTogglePlay,
          ),
          const SizedBox(width: AppTheme.md),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: isSwitching
                ? Container(
                    key: const ValueKey<String>('switching'),
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      color: AppTheme.bgCardLight,
                    ),
                    padding: const EdgeInsets.all(AppTheme.sm),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        AppTheme.accentSecondary,
                      ),
                    ),
                  )
                : _MiniActionButton(
                    key: const ValueKey<String>('switch'),
                    icon: Icons.swap_horiz_rounded,
                    onTap: onSwitchStream,
                  ),
          ),
        ],
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
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            color: AppTheme.bgCardLight,
            border: Border.all(color: AppTheme.bgCardLight, width: 1),
          ),
          child: Icon(widget.icon, size: 20, color: AppTheme.accentSecondary),
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
