# Study Pulse

Study Pulse is a Flutter focus app with Firebase Auth, Firestore session tracking, and a data-driven Insights Dashboard.

## Features

- Email/password authentication with Firebase.
- Smart focus timer with background distraction tracking.
- Focus history from Firestore.
- Insights Dashboard with basic ML-style analysis.
- Auto planner that generates study blocks and breaks from user inputs.

## Insights Dashboard

The dashboard has two sections:

1. Your Insights
2. Today's Plan

### Your Insights

Firestore-backed metrics shown in clean card UI:

- Total study time
- Average focus score
- Best study time

ML-style logic (simulated, rules-based):

- Reads past focus sessions from Firestore.
- Groups sessions by time of day (Morning/Afternoon/Evening/Night).
- Computes the best 2-hour window with the highest average focus score.
- Displays recommendations like: `You focus best at 8 PM-10 PM`.

This prepares the app for a future upgrade to real ML inference without changing the user-facing feature shape.

### Today's Plan (Auto Plan Generator)

User inputs:

- Subjects/tasks (comma or newline separated)
- Available start/end time range

Generated plan behavior:

- Splits study time into 25-45 minute sessions.
- Inserts 5-10 minute breaks.
- Assigns subjects sequentially across sessions.

## Firestore Data Model

Collection: `focus_sessions`

Example fields:

- `focus_score` (double)
- `session_duration` (int, seconds)
- `distraction_duration` (int, seconds)
- `timestamp` (server timestamp)
- `session_started_at` (timestamp)
- `subject` (string, optional)
- `user_id` (string, optional)

## Setup

1. Install Flutter dependencies.
2. Configure Firebase for Android/iOS/Web.
3. Add platform Firebase config files.
4. Run the app.

```bash
flutter pub get
flutter run
```

## Architecture & Design System

### UI/UX Design System

- **Theme**: Dark-first design with clean, professional aesthetic
- **Color Palette**: 
  - Background: #0F1218
  - Cards: #1A1F2B
  - Accent: #4F7CFF
- **Typography**: Inter font (600 bold, 500 secondary, 400 body)
- **Components**: ModernCard, GlassCard, PrimaryButton, status labels

### State Management

- **Backend**: Firebase Firestore for data persistence
- **Authentication**: Firebase Auth (email/password)
- **Local State**: Stream subscriptions and service-based state management

## Future Implementation

### Phase 1: Enhanced Analytics
- [ ] **Real ML Model Integration**: Replace rule-based focus time prediction with ML inference
- [ ] **User Preference Learning**: Train personalized models based on historical session patterns
- [ ] **Advanced Recommendations**: Suggest optimal study times, session lengths, and subject sequencing

### Phase 2: Social & Gamification
- [ ] **Study Groups**: Collaborative session management and shared planner views
- [ ] **Achievements & Badges**: Milestone tracking and gamified progress indicators
- [ ] **Leaderboards**: Optional anonymous or friend-based study streaks

### Phase 3: Platform & Device Support
- [ ] **Web App**: Flutter Web build with synchronized session data
- [ ] **Desktop Support**: Windows/macOS native apps
- [ ] **Wearables Integration**: Apple Watch / Wear OS status sync
- [ ] **Push Notifications**: Reminders for upcoming sessions and daily summaries

### Phase 4: Advanced Features
- [ ] **Focus Session Analytics**: Session-level distraction metrics and quality scoring
- [ ] **Smart Breaks**: Recommended break activities and stretch reminders
- [ ] **Calendar Integration**: Google Calendar / Outlook sync for schedule planning
- [ ] **Focus Mode**: Do Not Disturb / app blocking during active sessions
- [ ] **Export & Reporting**: PDF session history and performance summaries

### Phase 5: Accessibility & Localization
- [ ] **Multi-language Support**: i18n for major languages
- [ ] **Accessibility Improvements**: Screen reader support, keyboard navigation
- [ ] **Themes**: Additional light/high-contrast theme options

## Troubleshooting

### Common Issues

**"Cannot sign in with Firebase"**
- Ensure Firebase config files (`google-services.json` for Android, `GoogleService-Info.plist` for iOS) are present
- Verify Firebase project credentials in Firebase Console

**"Firestore data not syncing"**
- Check internet connection
- Verify Firestore security rules allow read/write for authenticated users
- Check user authentication status in Firebase Console

**"Timer not persisting after app restart"**
- Verify TimerQueueState is saved to Firestore before backgrounding
- Check for app kill signals in logcat/Console

### Configuration Notes

- Analytics filter to completed sessions only (skipped/incomplete excluded from metrics)
- Status labels use text-based indicators ("Completed", "Skipped", "Up Next") for clarity
- Early plan termination marks remaining blocks as "Skipped" automatically

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Create a feature branch: `git checkout -b feature/your-feature-name`
2. Ensure Dart formatting: `dart format lib/`
3. Run analysis: `dart analyze`
4. Submit a pull request with a clear description

## Notes

- The current analytics layer is deterministic and data-driven (ML-style simulation).
- The architecture is ready to swap in a real ML model later (for prediction and planning recommendations).
- Design system is locked to ensure consistency across all screens (see "UI/UX Design System" section).
