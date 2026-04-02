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

## Notes

- The current analytics layer is deterministic and data-driven (ML-style simulation).
- The architecture is ready to swap in a real ML model later (for prediction and planning recommendations).
