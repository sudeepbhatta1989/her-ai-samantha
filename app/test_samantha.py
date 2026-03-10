#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════
  SAMANTHA APP — LAMBDA API TEST SUITE
  Zero dependencies — uses only Python built-ins (urllib)
  Works with any Python 3 install, no pip needed.

  HOW TO RUN (Windows PowerShell):
    python test_samantha.py
  OR if 'python' not found:
    py test_samantha.py
═══════════════════════════════════════════════════════════
"""

import json
import time
import sys
import urllib.request
import urllib.error
from datetime import datetime

LAMBDA_URL = "https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat"
USER_ID    = "user1"
TIMEOUT    = 30  # seconds per request

# ── Console colours (work in Windows Terminal / PowerShell 7+) ──
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"
DIM    = "\033[2m"

results = []

# ── HTTP helper using only urllib ────────────────────────
def call(action=None, extra=None, message=None):
    payload = {"userId": USER_ID}
    if action:   payload["action"] = action
    if extra:    payload.update(extra)
    if message:  payload["message"] = message
    try:
        data = json.dumps(payload).encode("utf-8")
        req  = urllib.request.Request(
            LAMBDA_URL,
            data    = data,
            headers = {"Content-Type": "application/json"},
            method  = "POST",
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return resp.status, body
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode("utf-8"))
        except Exception:
            body = {"error": str(e)}
        return e.code, body
    except Exception as e:
        return None, {"error": str(e)}

# ── Test assertion helper ────────────────────────────────
def check(name, status, body, must_have_keys=None,
          value_check=None, warn_only=False):
    ok    = True
    notes = []

    if status is None:
        ok = False
        notes.append(f"Request failed: {body.get('error','?')}")
    elif status != 200:
        ok = False
        notes.append(f"HTTP {status}")

    if ok and body.get("status") == "error" and not warn_only:
        ok = False
        notes.append(f"Lambda error: {body.get('error','?')}")

    if ok and must_have_keys:
        for k in must_have_keys:
            if k not in body:
                ok = False
                notes.append(f"Missing key: '{k}'")

    if ok and value_check:
        try:
            passed, msg = value_check(body)
            if not passed:
                ok = False
                notes.append(msg)
        except Exception as e:
            ok = False
            notes.append(f"check threw: {e}")

    effective_ok = ok or warn_only
    icon  = f"{GREEN}✓{RESET}" if ok else (f"{YELLOW}⚠{RESET}" if warn_only else f"{RED}✗{RESET}")
    note_str = f"  {DIM}→ {'; '.join(notes)}{RESET}" if notes else ""
    print(f"  {icon}  {name}{note_str}")
    results.append({"name": name, "ok": ok, "warn": warn_only and not ok})
    return ok, body

def section(n, title):
    print(f"\n{BOLD}[ {n} ] {title}{RESET}")

# ════════════════════════════════════════════════════════
print(f"\n{BOLD}{CYAN}╔══════════════════════════════════════════════════╗{RESET}")
print(f"{BOLD}{CYAN}║   SAMANTHA LAMBDA API TEST SUITE                ║{RESET}")
print(f"{BOLD}{CYAN}║   {datetime.now().strftime('%Y-%m-%d  %H:%M:%S')} IST                 ║{RESET}")
print(f"{BOLD}{CYAN}╚══════════════════════════════════════════════════╝{RESET}")

# ── 1. CONNECTIVITY ──────────────────────────────────────
section(1, "CONNECTIVITY — Lambda reachable?")
s, b = call("get_streaks")

if s is None:
    print(f"  {RED}✗  Network error — cannot reach Lambda: {b.get('error','?')}{RESET}")
    print(f"  {RED}  Check internet / AWS / VPN.{RESET}")
    sys.exit(1)
elif s == 500:
    print(f"  {RED}✗  HTTP 500 — Lambda is CRASHING on the server.{RESET}")
    print(f"  {YELLOW}  The OLD handler.py is still deployed (ask_groq fix not live yet).{RESET}")
    print(f"  {DIM}  Error body: {json.dumps(b)[:300]}{RESET}")
    print()
    print(f"  {BOLD}TO FIX:{RESET}")
    print(f"  {CYAN}  Run deploy.bat → [1] Lambda only{RESET}")
    print(f"  {CYAN}  (or manually upload the new handler.py to AWS){RESET}")
    print()
    print(f"  {BOLD}TO SEE THE CRASH LOG:{RESET}")
    print(f"  {CYAN}  aws logs tail /aws/lambda/her-ai-brain --region ap-south-1 --since 10m{RESET}")
    print()
    print(f"  {DIM}Re-run test_samantha.py after deploying.{RESET}")
    print(f"\n{BOLD}{'=' * 52}{RESET}")
    print(f"{RED}  VERDICT: Deploy Lambda first → then re-run tests.{RESET}")
    print(f"{BOLD}{'=' * 52}{RESET}")
    sys.exit(1)
else:
    check("Lambda responds HTTP 200", s, b)

# ── 2. ASK GROQ — core fix ──────────────────────────────
section(2, "CHAT — ask_groq return fix (was 'Try again')")
print(f"  {DIM}Calls Groq LLM — may take 5-15s{RESET}")
s, b = call(message="What are my pending tasks for today?")
check("HTTP 200",                s, b, must_have_keys=["reply"])
check("reply is non-empty",      s, b,
      value_check=lambda b: (
          isinstance(b.get("reply"), str) and len(b.get("reply","")) > 10,
          f"reply={repr(b.get('reply',''))[:80]}"))
check("reply is NOT 'Try again'", s, b,
      value_check=lambda b: (
          "Try again" not in b.get("reply","") and
          "Samantha is thinking" not in b.get("reply",""),
          f"got fallback reply: {repr(b.get('reply',''))[:80]}"))
print(f"  {DIM}→ Samantha said: \"{str(b.get('reply',''))[:100]}...\"{RESET}")

# ── 3. MORNING BRIEFING ──────────────────────────────────
section(3, "MORNING BRIEFING")
s, b = call("morning_briefing")
check("HTTP 200",                s, b, must_have_keys=["briefing"])
check("briefing non-empty",      s, b,
      value_check=lambda b: (
          isinstance(b.get("briefing"), str) and len(b.get("briefing","")) > 20,
          f"briefing={repr(b.get('briefing',''))[:60]}"))
check("plan included",           s, b, must_have_keys=["plan"], warn_only=True)

# ── 4. GET PLAN ──────────────────────────────────────────
section(4, "GET PLAN")
s, b = call("get_plan")
check("HTTP 200",                s, b)
plan = b.get("plan")
check("plan returned",           s, b,
      value_check=lambda b: (b.get("plan") is not None,
                              "plan is None — no plan in Firestore yet"), warn_only=True)
if plan and isinstance(plan, dict):
    total_slots = sum(len(plan.get(k, [])) for k in ["morning","afternoon","evening"])
    check(f"plan has task slots ({total_slots} total)", s, b,
          value_check=lambda b: (total_slots > 0, "all slot arrays empty"))
    check("completed_tasks is a list", s, b,
          value_check=lambda b: (
              isinstance(b.get("plan",{}).get("completed_tasks"), list),
              f"type={type(b.get('plan',{}).get('completed_tasks'))}"))
    done_count = len(plan.get("completed_tasks", []))
    print(f"  {DIM}→ {done_count} task(s) already completed today{RESET}")

# ── 5. MARK TASK DONE — persistence ─────────────────────
section(5, "MARK TASK DONE — persistence (tab-switch fix)")
TEST_TASK = "__test_ping_samantha__"

s, b = call("mark_task_done", {"task": TEST_TASK})
check("mark_task_done HTTP 200",      s, b, must_have_keys=["completed_tasks"])
check("task in completed_tasks list", s, b,
      value_check=lambda b: (TEST_TASK in b.get("completed_tasks", []),
                              f"got: {b.get('completed_tasks')}"))

# Round-trip: fetch plan and confirm task survived in Firestore
time.sleep(1)
s2, b2 = call("get_plan")
if b2.get("plan"):
    survived = TEST_TASK in b2.get("plan",{}).get("completed_tasks",[])
    check("✦ tick PERSISTS in Firestore after get_plan", s2, b2,
          value_check=lambda b: (
              TEST_TASK in b.get("plan",{}).get("completed_tasks",[]),
              f"LOST — completed_tasks={b.get('plan',{}).get('completed_tasks',[])}"))
    if survived:
        print(f"  {GREEN}  → This is the fix for '0/6 tasks after tab switch'{RESET}")
    else:
        print(f"  {RED}  → Still broken! Lambda not deployed yet?{RESET}")
else:
    check("tick persists (no plan doc yet to verify)", s2, b2, warn_only=True)

# ── 6. UNMARK TASK (undo) ────────────────────────────────
section(6, "UNMARK TASK — undo support")
s, b = call("unmark_task_done", {"task": TEST_TASK})
check("unmark_task_done HTTP 200",    s, b, must_have_keys=["completed_tasks"])
check("task removed from list",       s, b,
      value_check=lambda b: (TEST_TASK not in b.get("completed_tasks",[]),
                              f"still in list: {b.get('completed_tasks')}"))

# ── 7. GENERATE PLAN (AI) ────────────────────────────────
section(7, "GENERATE PLAN (AI)")
print(f"  {DIM}Calls Groq to generate today's plan — may take 15-25s{RESET}")
s, b = call("generate_plan")
check("HTTP 200",                     s, b, must_have_keys=["plan"])
if b.get("plan"):
    p = b["plan"]
    total = sum(len(p.get(k,[])) for k in ["morning","afternoon","evening"])
    check(f"plan has tasks ({total} slots generated)", s, b,
          value_check=lambda b: (total > 0, "zero tasks in generated plan"))
    check("top_priority set",         s, b,
          value_check=lambda b: (bool(b.get("plan",{}).get("top_priority")),
                                  "top_priority missing/empty"))
    check("completed_tasks starts []",s, b,
          value_check=lambda b: (b.get("plan",{}).get("completed_tasks") == [],
                                  f"completed_tasks={b.get('plan',{}).get('completed_tasks')}"),
          warn_only=True)

# ── 8. HABIT STREAKS ─────────────────────────────────────
section(8, "HABIT STREAKS — home screen counters")
s, b = call("get_streaks")
check("HTTP 200",                     s, b, must_have_keys=["streaks"])
check("streaks is a dict",            s, b,
      value_check=lambda b: (isinstance(b.get("streaks"), dict),
                              f"type={type(b.get('streaks'))}"))
streaks = b.get("streaks", {})
for habit in ["daily_short", "sketch", "ukulele", "exercise"]:
    val = streaks.get(habit, {})
    streak_val = val.get("current_streak", 0) if isinstance(val, dict) else 0
    icon = "🔥" if streak_val > 0 else "○"
    print(f"  {DIM}→ {habit}: {icon} {streak_val} day streak{RESET}")

# ── 9. MARK HABIT DONE ───────────────────────────────────
section(9, "MARK HABIT DONE — streak increment")
s, b = call("mark_habit", {"habit": "exercise"})
check("HTTP 200",                     s, b, must_have_keys=["streak_data"])
check("streak_data has current_streak", s, b,
      value_check=lambda b: ("current_streak" in b.get("streak_data",{}),
                              f"streak_data={b.get('streak_data')}"))
streak = b.get("streak_data",{}).get("current_streak", 0)
check(f"streak ≥ 1 (got {streak})",  s, b,
      value_check=lambda b: (b.get("streak_data",{}).get("current_streak",0) >= 1,
                              "streak is 0 after marking"))

# ── 10. HISTORY ──────────────────────────────────────────
section(10, "HISTORY — was blank, now fixed")
s, b = call("get_history")
check("HTTP 200",                     s, b, must_have_keys=["sessions"])
check("sessions is a list",           s, b,
      value_check=lambda b: (isinstance(b.get("sessions"), list),
                              f"type={type(b.get('sessions'))}"))
sessions = b.get("sessions", [])
print(f"  {DIM}→ {len(sessions)} conversation session(s) found{RESET}")
if sessions:
    s0 = sessions[0]
    check("session has required keys", s, b,
          value_check=lambda b: (
              all(k in (b.get("sessions") or [{}])[0] for k in ["id","messages"]),
              f"keys={list(s0.keys())}"))
    msg_count = len(s0.get("messages", []))
    print(f"  {DIM}→ Most recent session has {msg_count} message(s){RESET}")

# ── 11. SAVE FCM TOKEN ───────────────────────────────────
section(11, "FCM TOKEN SAVE — notifications fix")
s, b = call("save_fcm_token", {"token": "test_token_suite_verify_abc123"})
check("HTTP 200",                     s, b)
check("saved successfully",           s, b,
      value_check=lambda b: (b.get("status") == "ok" or b.get("saved") is True,
                              f"status={b.get('status')} saved={b.get('saved')}"))

# ── 12. SEND NOTIFICATION (dry-run) ─────────────────────
section(12, "SEND NOTIFICATION (dry-run — fake token OK)")
s, b = call("send_notification", {
    "title":       "✦ Test from test_samantha.py",
    "body":        "If you see this, FCM is wired up correctly!",
    "tab":         "talk",
    "target_user": USER_ID,
})
# status=error is EXPECTED here (fake token) — mark both as warn_only
check("HTTP 200",                     s, b, warn_only=True)
status = b.get("status","?")
check("returns ok/no_token/error (fake token → error expected)", s, b,
      value_check=lambda b: (b.get("status") in ("ok","no_token","error"),
                              f"unknown status={status}"),
      warn_only=True)
if status == "no_token":
    print(f"  {DIM}→ no_token: no FCM token saved yet. Normal before first app launch.{RESET}")
elif status == "ok":
    print(f"  {GREEN}  → FCM push sent! message_id={b.get('message_id')}{RESET}")
elif status == "error":
    err = b.get('error','')
    if 'not a valid FCM' in err or 'registration token' in err.lower():
        print(f"  {DIM}→ Expected: fake test token rejected by Firebase. Real token set on first app launch.{RESET}")
    else:
        print(f"  {YELLOW}  → FCM error: {err[:100]}{RESET}")

# ── 13. WEEKLY REFLECTION ────────────────────────────────
section(13, "JARVIS — WEEKLY REFLECTION")
s, b = call("get_weekly_reflection")
check("HTTP 200",                     s, b)
check("no hard error",                s, b,
      value_check=lambda b: ("error" not in b or b.get("status") != "error",
                              f"error: {b.get('error','')}"), warn_only=True)
ref = b.get("reflection") or b.get("weekly_reflection")
if ref:
    print(f"  {DIM}→ reflection exists ({len(str(ref))} chars){RESET}")
else:
    print(f"  {DIM}→ no reflection yet (normal if weekly trigger not fired){RESET}")

# ════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ════════════════════════════════════════════════════════
total      = len(results)
passed     = sum(1 for r in results if r["ok"])
failed     = sum(1 for r in results if not r["ok"] and not r["warn"])
warned     = sum(1 for r in results if r["warn"])

print(f"\n{BOLD}{'═'*52}{RESET}")
bar = "█" * int(passed / total * 20) + "░" * (20 - int(passed / total * 20))
pct = int(passed / total * 100)
color = GREEN if failed == 0 else (YELLOW if failed <= 2 else RED)
print(f"{BOLD}  {color}[{bar}] {pct}%  {passed}/{total} passed{RESET}", end="")
if failed: print(f"  {RED}{failed} FAILED{RESET}", end="")
if warned: print(f"  {YELLOW}{warned} warning(s){RESET}", end="")
print(f"\n{BOLD}{'═'*52}{RESET}")

if failed:
    print(f"\n{RED}FAILED:{RESET}")
    for r in results:
        if not r["ok"] and not r["warn"]:
            print(f"  {RED}✗  {r['name']}{RESET}")
    print(f"\n{YELLOW}Tip: Deploy handler.py to Lambda first, then re-run.{RESET}")
    print(f"{YELLOW}     Run deploy.bat → [1] Lambda only{RESET}")
    sys.exit(1)
else:
    print(f"\n{GREEN}✅  All tests passed. Safe to push Flutter to Codemagic.{RESET}")
    if warned:
        print(f"{YELLOW}    {warned} warning(s) above are non-blocking (empty Firestore etc.){RESET}")
    sys.exit(0)
