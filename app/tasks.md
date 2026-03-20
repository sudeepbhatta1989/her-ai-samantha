# Samantha AI Agent Task Queue
# Format: - [ ] PRIORITY: description
# Priorities: HIGH | MED | LOW

## Pending

- [~] HIGH: Fix GROQ_API_KEY not loading in samantha_brain.py. Add python-dotenv, call load_dotenv() at module startup, verify Groq client uses os.getenv correctly
- [ ] HIGH: Fix GitHub Actions iOS build codesign error. Switch flutter build ios to use --simulator --debug flag instead of --release --no-codesign
- [ ] HIGH: Add ScheduleScreen to bottom navigation in lib/main.dart - import schedule_screen.dart, add NavigationDestination with calendar_today_rounded icon, add ScheduleScreen to pages list
- [ ] MED: Update _backendUrl in lib/services/schedule_service.dart to read from environment or use local IP
- [ ] MED: Wire /brain/command into processNaturalLanguage in schedule_service.dart
- [ ] MED: Add ChangeNotifierProvider wrapping MaterialApp in main.dart for ScheduleProvider
- [ ] MED: Add schedule router to FastAPI main.py - from schedule_api import router as schedule_router
- [ ] LOW: Fix dart:html import in lib/screens/chat_screen.dart line 5
- [ ] LOW: Add python-dotenv to backend requirements.txt and load .env in main.py

## In Progress

## Done
