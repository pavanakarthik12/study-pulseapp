import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import 'widgets/ui_shell.dart';

class StudyTimerScreen extends StatefulWidget {
  const StudyTimerScreen({super.key});

  @override
  State<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends State<StudyTimerScreen> {
  static const int _defaultSeconds = 25 * 60;

  Timer? _timer;
  int _remainingSeconds = _defaultSeconds;
  bool _isRunning = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_isRunning) {
      return;
    }
    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _isRunning = false;
        });
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
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _defaultSeconds;
    });
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
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                        color: const Color(0xFF7C9BFF).withValues(alpha: 0.35),
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
                          style:
                              Theme.of(context).textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isFinished ? 'Session complete' : 'Focus timer',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                        ),
                      ],
                    ),
                  ),
                )
                    .animate()
                    .fade(duration: 500.ms)
                    .scale(begin: const Offset(0.92, 0.92), duration: 500.ms),
                const SizedBox(height: 40),
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