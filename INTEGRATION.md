# SAMANTHA SCHEDULE MODULE — INTEGRATION GUIDE
# Google Calendar + Apple Calendar + AI Briefing + Conflict Detection

## FILES IN THIS ZIP

```
flutter/
  lib/
    models/
      schedule_event.dart       ← Data models
    services/
      schedule_service.dart     ← Firestore CRUD + AI briefing calls
      calendar_sync_service.dart← Google + Apple Calendar sync
    providers/
      schedule_provider.dart    ← State management (ChangeNotifier)
    screens/
      schedule_screen.dart      ← Main schedule UI (Day/Week/AI Chat tabs)
    widgets/schedule/
      event_tile.dart           ← Event row widget
      widgets.dart              ← ConflictCard, BriefingBanner, WeekStrip, AddEventSheet

backend/
  schedule_api.py               ← FastAPI router (add to your existing app)
```

---

## STEP 1 — pubspec.yaml

Add these dependencies:

```yaml
dependencies:
  device_calendar: ^4.3.0    # reads iOS/Android native calendars
  provider: ^6.1.2
  http: ^1.2.0
  intl: ^0.19.0
  cloud_firestore: ^4.x.x    # already in your project
```

Run: `flutter pub get`

---

## STEP 2 — iOS Permissions (REQUIRED for Apple/Google Calendar)

In `ios/Runner/Info.plist` add:

```xml
<key>NSCalendarsUsageDescription</key>
<string>Samantha needs calendar access to sync and manage your events.</string>
<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>Samantha needs write access to create calendar events for you.</string>
```

---

## STEP 3 — Copy Flutter Files

Copy all `flutter/lib/` files into `app/lib/` maintaining the same subdirectory structure:
- `models/schedule_event.dart`
- `services/schedule_service.dart`
- `services/calendar_sync_service.dart`
- `providers/schedule_provider.dart`
- `screens/schedule_screen.dart`
- `widgets/schedule/event_tile.dart`
- `widgets/schedule/widgets.dart`

---

## STEP 4 — Wire Up Schedule Screen

In your bottom navigation (wherever you have tabs/nav), add:

```dart
import 'screens/schedule_screen.dart';

// In your navigation items list:
NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Schedule'),

// In your page/body switcher:
ScheduleScreen(),
```

Wrap your MaterialApp or the widget tree with ChangeNotifierProvider:

```dart
import 'package:provider/provider.dart';
import 'providers/schedule_provider.dart';

// Wrap your app:
ChangeNotifierProvider(
  create: (_) => ScheduleProvider(),
  child: MaterialApp(...),
)
```

---

## STEP 5 — Configure Your Backend URL

In `lib/services/schedule_service.dart`, change line 20:
```dart
// FROM:
static const String _backendUrl = 'https://your-samantha-backend.com';
// TO:
static const String _backendUrl = 'https://YOUR_ACTUAL_BACKEND_URL';
```

---

## STEP 6 — Wire Firebase Auth UID

In both service files, replace the placeholder user ID:

**schedule_service.dart** line 19:
```dart
static const String _userId = 'default_user';
// Replace with:
static String get _userId => FirebaseAuth.instance.currentUser?.uid ?? 'default_user';
```

**calendar_sync_service.dart** line 14:
```dart
static const String _userId = 'default_user';
// Replace with:
static String get _userId => FirebaseAuth.instance.currentUser?.uid ?? 'default_user';
```

---

## STEP 7 — Backend Setup

Copy `backend/schedule_api.py` to your backend directory.

Add to `requirements.txt`:
```
groq>=0.5.0
python-dateutil>=2.8.0
```

Run: `pip install -r requirements.txt`

In your main FastAPI app file:
```python
from schedule_api import router as schedule_router
app.include_router(schedule_router)
```

Set environment variable:
```bash
# Windows:
set GROQ_API_KEY=your_key_here

# Or in .env file:
GROQ_API_KEY=your_key_here
```

Get a free GROQ key at: https://console.groq.com

---

## STEP 8 — Firestore Security Rules

Add to your Firestore rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/schedule/{eventId} {
      allow read, write: if request.auth.uid == userId;
    }
  }
}
```

---

## HOW CALENDAR SYNC WORKS

When user taps **Sync** in the Schedule screen:

1. Requests calendar permission (iOS native dialog)
2. Reads all calendars from the device via `device_calendar`
   - Gmail-linked accounts → tagged as `googleCalendar`
   - iCloud/Apple accounts → tagged as `appleCalendar`
3. Fetches events for next 14 days
4. Writes them to Firestore: `users/{uid}/schedule/{gcal_eventId}`
5. Shows coloured source indicators: 🔴 Google, ⚪ Apple, 🟣 Samantha

**Write-back** (optional — create events on device calendar):
```dart
await CalendarSyncService.instance.createExternalEvent(
  event: myEvent,
  calendarId: 'your_calendar_id_from_getAvailableCalendars',
);
```

---

## CONFLICT DETECTION

Runs automatically whenever the briefing loads. Algorithm:
- Compares all pairs of events on the selected day O(n²)
- Any two events where `startA < endB && endA > startB` = conflict
- Picks the lower-priority event to suggest rescheduling
- Finds free 30-min+ slots between 8am–8pm
- Shows `ConflictCard` with Accept button — one tap reschedules in Firestore

---

## FIX THE dart:html BUILD ERROR

While you're in `chat_screen.dart`, fix the existing build error:

```dart
// Remove this line:
import 'dart:html';

// Add instead:
import 'package:flutter/foundation.dart';

// Replace any html usage like window.location with:
if (kIsWeb) { /* web-only code */ }
```

---

## QUESTIONS?

The module is self-contained and doesn't break any existing screens.
The only new package that touches native iOS APIs is `device_calendar`.
Everything else is pure Dart/Firestore.
