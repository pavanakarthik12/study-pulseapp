import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_gate.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/study_timer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudyPulseApp());
}

class StartupErrorView extends StatelessWidget {
  const StartupErrorView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeepDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Firebase Setup Required',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.md),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.lg),
              Text(
                'Add android/app/google-services.json and ios/Runner/GoogleService-Info.plist, then restart.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OfflineModeScreen extends StatelessWidget {
  const OfflineModeScreen({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeepDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.lg),
          child: Column(
            children: [
              const Spacer(),
              Text(
                'Study Pulse',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.md),
              Text(
                'Running in offline mode',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.md),
              Text(
                'Authentication is unavailable until Firebase config files are added.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.xl),
              Text(
                reason,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppTheme.lg),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StudyTimerScreen(),
                      ),
                    );
                  },
                  child: const Text('Start Focus Session'),
                ),
              ),
              const SizedBox(height: AppTheme.md),
              Text(
                'Add android/app/google-services.json and ios/Runner/GoogleService-Info.plist to re-enable login.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<String?> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeFirebase();
  }

  Future<String?> _initializeFirebase() async {
    try {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        // Android/iOS read Firebase config from native files.
        await Firebase.initializeApp();
      }
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? error.code;
    } catch (error) {
      return error.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingView();
        }

        final errorMessage = snapshot.data;
        if (errorMessage != null) {
          return OfflineModeScreen(reason: errorMessage);
        }

        return const AuthGate();
      },
    );
  }
}

class _StartupLoadingView extends StatelessWidget {
  const _StartupLoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeepDark,
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class StudyPulseApp extends StatelessWidget {
  const StudyPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Study Pulse',
      theme: AppTheme.buildTheme(),
      home: const AppBootstrap(),
    );
  }
}
