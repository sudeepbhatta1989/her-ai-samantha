# HER AI — Phase Deploy Checklist

Run `health_check.bat` after every phase. Target: **all tests green** before moving to next phase.

---

## Standard Deploy Order (every phase)

```
1. Copy new files to backend\lambda\ and app\lib\
2. Run deploy_phase_XX.bat  (Lambda deploy)
3. Run health_check.bat     ← catches issues immediately
4. Fix any FAIL tests
5. git add + commit + push  (Flutter deploy)
6. Wait for Codemagic build (check codemagic.io/apps)
7. Install from TestFlight + manual smoke test on iPhone
```

---

## Health Check Commands

| Command | When to use |
|---------|-------------|
| `health_check.bat` | Full check after any deploy (~2 min) |
| `py health_check.py --quick` | Fast sanity check — chat + streaks only (15 sec) |
| `py health_check.py --phase de` | Phase D+E specific tests only |

---

## What Each Test Checks

### Section 1 — Core Brain (15 tests)
| Test | What breaks if it fails |
|------|------------------------|
| Chat basic reply | Lambda import error / Groq down |
| Intent stays chat | Plan gets wiped when asking questions |
| get_streaks | Habit tab shows nothing |
| get_plan | Plan tab shows empty |
| get_plan_for_date | Tomorrow plan broken |
| get_history | History tab empty |
| get_weekly_reflection | Jarvis brain shows "no reflections" |
| get_research_reports | Jarvis research tab empty |
| get_projects | Jarvis projects tab empty |
| get_agent_logs | Jarvis logs tab empty |
| get_profile | Samantha doesn't know user context |
| morning_briefing | Home screen shows nothing |
| get_cached_briefing | Home screen slow to load (Phase E) |
| mark_habit | Habit streaks not updating |
| Tomorrow WFH routing | Tomorrow plan not regenerating on WFH message |

### Section 2 — Phase D (2 tests)
| Test | What breaks if it fails |
|------|------------------------|
| her-ai-reflection invokes | Sunday 9pm reflection never runs |
| No cryptography error | Lambda package broken |

### Section 3 — Phase E (2 tests)
| Test | What breaks if it fails |
|------|------------------------|
| her-ai-briefing invokes | No pre-cached briefing, slow home screen |
| Briefing cached in Firestore | Home screen falls back to live generation |

### Section 4 — EventBridge (2 tests)
| Test | What breaks if it fails |
|------|------------------------|
| her-ai-weekly-reflection ENABLED | No automatic Sunday reflection |
| her-ai-daily-briefing ENABLED | No automatic morning briefing |

### Section 5 — Quality (3 tests)
| Test | What breaks if it fails |
|------|------------------------|
| No raw error to user | User sees "ImportModuleError" in chat |
| Response under 15s | App feels broken / timeout |
| Non-empty reply | Samantha sends blank messages |

---

## Common Failures + Fixes

| Error seen in test | Cause | Fix |
|-------------------|-------|-----|
| `ImportModuleError: cryptography` | Wrong pip wheels (Windows vs Linux) | Run deploy with `--platform manylinux2014_x86_64` |
| `Failed to import google-cloud-firestore` | Missing Linux binary wheels | Check requirements.txt has all google-cloud-* packages |
| `No message provided` (from direct Lambda test) | Wrong payload format | Use `{"body": "{...}"}` for direct invoke, or test via API Gateway |
| `ResourceConflictException` | Lambda still in Pending state | Add wait loop polling `LastUpdateStatus` |
| `AccessDeniedException events:PutRule` | IAM user lacks EventBridge perms | Add `CloudWatchEventsFullAccess` to IAM user |
| History tab empty | Firestore index missing on timestamp | Use fallback unordered query |
| Plan shows yesterday's tasks | Date mismatch not caught | Plan screen sends today's date explicitly |

---

## Phase Status

| Phase | What | Health Check Section | Status |
|-------|------|---------------------|--------|
| A | Intent Classifier | Section 1 — Intent test | ✅ |
| B | Research Agent | Section 1 — get_research_reports | ✅ |
| C | Planner Agent | Section 1 — get_plan, generate_plan | ✅ |
| D | Weekly Reflection Lambda | Section 2 | ✅ |
| E | Daily Briefing Lambda | Section 3 + Section 1 get_cached_briefing | ✅ |
| F | Approval Workflow | Section 1 — get_agent_logs (pending Phase F tests) | ⏳ |
| G | Strategy + Coding Agent | TBD | ⏳ |
| H | Semantic Memory (Pinecone) | TBD | ⏳ |
