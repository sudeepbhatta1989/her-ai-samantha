"""
samantha_brain.py
-----------------
Samantha's standalone schedule brain module.
Receives a natural language command, uses Groq to parse it,
resolves time references, checks Firestore for conflicts,
and executes the action.

Usage:
    from samantha_brain import SamanthaBrain
    brain = SamanthaBrain(groq_api_key="...", uid="samantha_personal_user")
    result = await brain.process("Move my gym to 7 PM tomorrow")

Add to FastAPI:
    from samantha_brain import SamanthaBrain, router as brain_router
    app.include_router(brain_router)

Endpoint:
    POST /brain/command
    { "command": "Move my gym to 7 PM tomorrow" }
"""

import os, json, re, logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from groq import AsyncGroq

# Load .env so GROQ_API_KEY and other vars are available in local dev
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # dotenv not installed — env vars must be set manually
from fastapi import APIRouter
from pydantic import BaseModel

# ── Firestore (optional — only imported if available) ─────────────────────────
try:
    from google.cloud import firestore as _fs
    _firestore_available = True
except ImportError:
    _firestore_available = False

logger = logging.getLogger("samantha.brain")

# ── FastAPI router ─────────────────────────────────────────────────────────────
router = APIRouter(prefix="/brain", tags=["brain"])


# ═══════════════════════════════════════════════════════════════════════════════
# REQUEST / RESPONSE MODELS
# ═══════════════════════════════════════════════════════════════════════════════

class CommandRequest(BaseModel):
    command: str
    uid: Optional[str] = "samantha_personal_user"
    context_time: Optional[str] = None  # ISO datetime, defaults to now

class CommandResponse(BaseModel):
    success: bool
    intent: str
    parsed: dict
    action_taken: str
    conflicts: list[str] = []
    message: str
    raw_command: str


# ═══════════════════════════════════════════════════════════════════════════════
# FEW-SHOT EXAMPLES  (selected from the 500 seeds — 2 per intent)
# ═══════════════════════════════════════════════════════════════════════════════

FEW_SHOT_EXAMPLES = [
    {"intent":"move_task",          "command":"Move my gym workout to 7 PM today",
     "output":{"intent":"move_task","title":"gym workout","newDate":"today","newTime":"19:00","durationMins":None}},
    {"intent":"move_task",          "command":"Reschedule my client call to next Monday morning",
     "output":{"intent":"move_task","title":"client call","newDate":"next_monday","newTime":"09:00","durationMins":None}},

    {"intent":"delay_task",         "command":"Push my team meeting 30 minutes later",
     "output":{"intent":"delay_task","title":"team meeting","delayMins":30,"newDate":None,"newTime":None}},
    {"intent":"delay_task",         "command":"Postpone my doctor appointment by 1 hour — something came up",
     "output":{"intent":"delay_task","title":"doctor appointment","delayMins":60,"newDate":None,"newTime":None}},

    {"intent":"advance_task",       "command":"Bring forward my deep work block by 1 hour",
     "output":{"intent":"advance_task","title":"deep work block","advanceMins":60,"newTime":None}},
    {"intent":"advance_task",       "command":"Move up my morning run to 6 AM",
     "output":{"intent":"advance_task","title":"morning run","advanceMins":None,"newTime":"06:00"}},

    {"intent":"swap_tasks",         "command":"Swap my gym session and team meeting",
     "output":{"intent":"swap_tasks","title1":"gym session","title2":"team meeting"}},
    {"intent":"swap_tasks",         "command":"Switch the times of my yoga class and client call",
     "output":{"intent":"swap_tasks","title1":"yoga class","title2":"client call"}},

    {"intent":"cancel_task",        "command":"Cancel my ukulele practice tonight",
     "output":{"intent":"cancel_task","title":"ukulele practice","date":"today"}},
    {"intent":"cancel_task",        "command":"Remove the dinner reservation from tomorrow",
     "output":{"intent":"cancel_task","title":"dinner reservation","date":"tomorrow"}},

    {"intent":"add_task",           "command":"Add a 1-hour deep work block tomorrow at 9 AM",
     "output":{"intent":"add_task","title":"deep work block","date":"tomorrow","time":"09:00","durationMins":60}},
    {"intent":"add_task",           "command":"Schedule gym for Saturday 7 AM",
     "output":{"intent":"add_task","title":"gym","date":"saturday","time":"07:00","durationMins":60}},

    {"intent":"smart_conditional",  "command":"Move my TravelerTree work to evening if nothing else comes up",
     "output":{"intent":"smart_conditional","title":"TravelerTree work","condition":"if_free","newTime":"19:00","newDate":None}},
    {"intent":"smart_conditional",  "command":"Reschedule sketch practice for tomorrow only if the morning is free",
     "output":{"intent":"smart_conditional","title":"sketch practice","condition":"if_free","newDate":"tomorrow","newTime":None}},

    {"intent":"conflict_resolution","command":"My team meeting and client call overlap — which should I move?",
     "output":{"intent":"conflict_resolution","title1":"team meeting","title2":"client call","action":"suggest_move"}},
    {"intent":"conflict_resolution","command":"Fix the clash between my gym session and standup call",
     "output":{"intent":"conflict_resolution","title1":"gym session","title2":"standup call","action":"auto_resolve"}},

    {"intent":"routine_adjustment", "command":"Move all my gym sessions 30 minutes earlier from now on",
     "output":{"intent":"routine_adjustment","title":"gym","shiftMins":-30,"scope":"recurring"}},
    {"intent":"routine_adjustment", "command":"Change my daily ukulele practice time to 10 PM permanently",
     "output":{"intent":"routine_adjustment","title":"ukulele practice","newTime":"22:00","scope":"recurring"}},

    {"intent":"bulk_rescheduling",  "command":"Push everything tomorrow afternoon back by 1 hour",
     "output":{"intent":"bulk_rescheduling","date":"tomorrow","timeWindow":"afternoon","delayMins":60}},
    {"intent":"bulk_rescheduling",  "command":"Clear my schedule for Saturday evening — I have plans",
     "output":{"intent":"bulk_rescheduling","date":"saturday","timeWindow":"evening","action":"clear"}},
]


SYSTEM_PROMPT = """You are Samantha's schedule parser. Your job is to convert a natural language schedule command into structured JSON.

Today's date and time: {now}

INTENTS:
- move_task: move a specific event to a new date/time
- delay_task: push an event later by N minutes/hours
- advance_task: pull an event earlier by N minutes/hours  
- swap_tasks: swap the time slots of two events
- cancel_task: cancel/remove an event (soft delete)
- add_task: create a new event
- smart_conditional: conditional reschedule ("if free", "if possible")
- conflict_resolution: resolve a scheduling conflict between two events
- routine_adjustment: change a recurring event's regular time
- bulk_rescheduling: reschedule multiple events at once

RELATIVE TIME RESOLUTION (resolve these to absolute values using today's date):
- today → {today}
- tomorrow → {tomorrow}
- tonight → {today} evening
- this weekend → nearest Saturday
- next Monday/Tuesday/etc → the next occurrence of that weekday
- in 2 hours → {in_2h}
- after lunch → {today} 13:00
- before dinner → {today} 18:00
- morning = 07:00-12:00, afternoon = 12:00-17:00, evening = 17:00-21:00, night = 21:00+

OUTPUT FORMAT — respond ONLY with valid JSON, no markdown, no extra text:
{{
  "intent": "<one of the 10 intents>",
  "confidence": 0.0-1.0,
  "title": "<event name or null>",
  "title2": "<second event name for swap/conflict or null>",
  "date": "<YYYY-MM-DD or null>",
  "newDate": "<YYYY-MM-DD or null>",
  "time": "<HH:MM 24h or null>",
  "newTime": "<HH:MM 24h or null>",
  "durationMins": <integer or null>,
  "delayMins": <positive integer or null>,
  "advanceMins": <positive integer or null>,
  "condition": "<if_free | if_confirmed | null>",
  "scope": "<once | recurring | null>",
  "timeWindow": "<morning | afternoon | evening | null>",
  "action": "<suggest_move | auto_resolve | clear | null>",
  "rawTimeRef": "<original time phrase from command>"
}}

FEW-SHOT EXAMPLES:
{examples}
"""


# ═══════════════════════════════════════════════════════════════════════════════
# SAMANTHA BRAIN
# ═══════════════════════════════════════════════════════════════════════════════

class SamanthaBrain:
    def __init__(self, groq_api_key: str = None, uid: str = "samantha_personal_user"):
        self.uid = uid
        self._groq = AsyncGroq(api_key=groq_api_key or os.getenv("GROQ_API_KEY", ""))
        self._db = None
        if _firestore_available:
            try:
                self._db = _fs.AsyncClient()
            except Exception as e:
                logger.warning(f"Firestore unavailable: {e}")

    # ── MAIN ENTRY POINT ──────────────────────────────────────────────────────

    async def process(self, command: str, context_time: str = None) -> CommandResponse:
        """
        Full pipeline: parse → resolve → conflict check → execute
        """
        now = datetime.fromisoformat(context_time) if context_time else datetime.now()

        # Step 1: Parse intent + entities via Groq
        parsed = await self._parse(command, now)
        intent = parsed.get("intent", "unknown")
        logger.info(f"Parsed intent={intent} confidence={parsed.get('confidence',0)}")

        # Step 2: Resolve relative dates to absolute
        parsed = self._resolve_dates(parsed, now)

        # Step 3: Conflict check (if Firestore available)
        conflicts = []
        if self._db and intent in ("move_task", "add_task", "advance_task", "delay_task"):
            conflicts = await self._check_conflicts(parsed)

        # Step 4: Execute
        action_taken = "none"
        message = ""
        success = False

        if conflicts and intent not in ("conflict_resolution", "smart_conditional"):
            message = (f"Conflict detected with: {', '.join(conflicts[:2])}. "
                      f"Suggest moving to a free slot instead.")
            action_taken = "conflict_blocked"
            success = False
        elif self._db:
            action_taken, message, success = await self._execute(intent, parsed, now)
        else:
            action_taken = "parsed_only"
            message = f"Parsed successfully (Firestore not connected): {intent}"
            success = True

        return CommandResponse(
            success=success,
            intent=intent,
            parsed=parsed,
            action_taken=action_taken,
            conflicts=conflicts,
            message=message,
            raw_command=command,
        )

    # ── STEP 1: PARSE ─────────────────────────────────────────────────────────

    async def _parse(self, command: str, now: datetime) -> dict:
        today = now.strftime("%Y-%m-%d")
        tomorrow = (now + timedelta(days=1)).strftime("%Y-%m-%d")
        in_2h = (now + timedelta(hours=2)).strftime("%Y-%m-%d %H:%M")

        # Build few-shot block (use 1 per intent = 10 examples for token efficiency)
        seen = set()
        examples_str = ""
        for ex in FEW_SHOT_EXAMPLES:
            if ex["intent"] not in seen:
                seen.add(ex["intent"])
                examples_str += (
                    f'Input: "{ex["command"]}"\n'
                    f'Output: {json.dumps(ex["output"])}\n\n'
                )

        system = SYSTEM_PROMPT.format(
            now=now.strftime("%Y-%m-%d %H:%M (%A)"),
            today=today, tomorrow=tomorrow, in_2h=in_2h,
            examples=examples_str,
        )

        try:
            resp = await self._groq.chat.completions.create(
                model="llama-3.1-70b-versatile",
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user",   "content": command},
                ],
                temperature=0.1,
                max_tokens=400,
            )
            raw = resp.choices[0].message.content.strip()
            raw = re.sub(r"```(?:json)?", "", raw).strip("` \n")
            return json.loads(raw)
        except Exception as e:
            logger.error(f"Parse error: {e}")
            return {"intent": "unknown", "confidence": 0.0}

    # ── STEP 2: RESOLVE DATES ─────────────────────────────────────────────────

    def _resolve_dates(self, parsed: dict, now: datetime) -> dict:
        """Convert relative date strings to YYYY-MM-DD if Groq didn't already."""
        def resolve(val: str) -> str:
            if not val or re.match(r'\d{4}-\d{2}-\d{2}', val):
                return val
            v = val.lower().strip()
            if v == "today":      return now.strftime("%Y-%m-%d")
            if v == "tomorrow":   return (now + timedelta(days=1)).strftime("%Y-%m-%d")
            if v == "yesterday":  return (now - timedelta(days=1)).strftime("%Y-%m-%d")
            days = {"monday":0,"tuesday":1,"wednesday":2,"thursday":3,
                    "friday":4,"saturday":5,"sunday":6}
            for day, wd in days.items():
                if day in v:
                    delta = (wd - now.weekday()) % 7 or 7
                    return (now + timedelta(days=delta)).strftime("%Y-%m-%d")
            return val

        for key in ("date", "newDate"):
            if parsed.get(key):
                parsed[key] = resolve(parsed[key])
        return parsed

    # ── STEP 3: CONFLICT CHECK ────────────────────────────────────────────────

    async def _check_conflicts(self, parsed: dict) -> list[str]:
        if not self._db:
            return []
        target_date = parsed.get("newDate") or parsed.get("date")
        target_time = parsed.get("newTime") or parsed.get("time")
        duration = parsed.get("durationMins") or 60

        if not target_date or not target_time:
            return []

        try:
            h, m = map(int, target_time.split(":"))
            start = datetime.strptime(target_date, "%Y-%m-%d").replace(hour=h, minute=m)
            end = start + timedelta(minutes=duration)

            day_start = start.replace(hour=0, minute=0, second=0)
            day_end = day_start + timedelta(days=1)

            col = self._db.collection("users").document(self.uid).collection("schedule")
            docs = col.where("startTime", ">=", day_start).where("startTime", "<", day_end).stream()
            conflicts = []
            async for doc in docs:
                d = doc.to_dict()
                if not d.get("isConfirmed", True):
                    continue
                ev_start = d["startTime"]
                ev_end   = d["endTime"]
                if ev_start < end and ev_end > start:
                    conflicts.append(d.get("title", "unnamed event"))
            return conflicts
        except Exception as e:
            logger.error(f"Conflict check error: {e}")
            return []

    # ── STEP 4: EXECUTE ───────────────────────────────────────────────────────

    async def _execute(self, intent: str, parsed: dict, now: datetime):
        if not self._db:
            return "skipped", "Firestore not available", False

        col = self._db.collection("users").document(self.uid).collection("schedule")

        try:
            if intent == "add_task":
                return await self._exec_add(col, parsed, now)
            elif intent in ("move_task", "advance_task", "delay_task"):
                return await self._exec_move(col, parsed, intent, now)
            elif intent == "cancel_task":
                return await self._exec_cancel(col, parsed, now)
            elif intent == "swap_tasks":
                return await self._exec_swap(col, parsed, now)
            elif intent == "conflict_resolution":
                return await self._exec_conflict(col, parsed, now)
            elif intent == "bulk_rescheduling":
                return await self._exec_bulk(col, parsed, now)
            elif intent == "routine_adjustment":
                return await self._exec_routine(col, parsed, now)
            elif intent == "smart_conditional":
                conflicts = await self._check_conflicts(parsed)
                if conflicts:
                    return "conditional_skipped", f"Slot taken by: {conflicts[0]}", False
                return await self._exec_move(col, parsed, "move_task", now)
            else:
                return "unknown_intent", f"Intent '{intent}' not yet handled", False
        except Exception as e:
            logger.error(f"Execute error: {e}")
            return "error", str(e), False

    async def _exec_add(self, col, parsed, now):
        date_str = parsed.get("date") or now.strftime("%Y-%m-%d")
        time_str = parsed.get("time") or "09:00"
        h, m = map(int, time_str.split(":"))
        start = datetime.strptime(date_str, "%Y-%m-%d").replace(hour=h, minute=m)
        end   = start + timedelta(minutes=parsed.get("durationMins") or 60)
        title = parsed.get("title") or "New event"

        await col.add({
            "title":         title,
            "startTime":     start,
            "endTime":       end,
            "category":      _guess_category(title),
            "priority":      "medium",
            "source":        "samantha",
            "aiGenerated":   True,
            "aiReason":      "User requested via voice command",
            "isConfirmed":   True,
            "tags":          [],
            "isRecurring":   False,
            "recurringRule": None,
        })
        return "added", f"Added '{title}' on {date_str} at {time_str}", True

    async def _exec_move(self, col, parsed, intent, now):
        title = parsed.get("title", "")
        docs = await _find_event(col, title, parsed.get("date") or now.strftime("%Y-%m-%d"))
        if not docs:
            return "not_found", f"Could not find '{title}' to move", False

        doc_ref, data = docs[0]
        old_start: datetime = data["startTime"]
        old_end:   datetime = data["endTime"]
        duration = old_end - old_start

        if intent == "delay_task":
            delay_m = parsed.get("delayMins") or 30
            new_start = old_start + timedelta(minutes=delay_m)
        elif intent == "advance_task":
            adv_m = parsed.get("advanceMins") or 30
            new_start = old_start - timedelta(minutes=adv_m)
        else:  # move_task
            new_date = parsed.get("newDate") or old_start.strftime("%Y-%m-%d")
            new_time = parsed.get("newTime") or old_start.strftime("%H:%M")
            h, m = map(int, new_time.split(":"))
            new_start = datetime.strptime(new_date, "%Y-%m-%d").replace(hour=h, minute=m)

        new_end = new_start + duration
        tags = list(data.get("tags") or [])
        if "modified_by_user" not in tags:
            tags.append("modified_by_user")

        await doc_ref.update({
            "startTime": new_start,
            "endTime":   new_end,
            "tags":      tags,
            "aiReason":  "Modified via user command",
        })
        return "moved", (f"Moved '{title}' to "
                        f"{new_start.strftime('%Y-%m-%d %H:%M')}"), True

    async def _exec_cancel(self, col, parsed, now):
        title = parsed.get("title", "")
        docs = await _find_event(col, title, parsed.get("date") or now.strftime("%Y-%m-%d"))
        if not docs:
            return "not_found", f"Could not find '{title}' to cancel", False

        doc_ref, data = docs[0]
        tags = list(data.get("tags") or [])
        if "cancelled" not in tags:
            tags.append("cancelled")
        await doc_ref.update({
            "isConfirmed": False,
            "tags":        tags,
            "aiReason":    "Cancelled via user command",
        })
        return "cancelled", f"Cancelled '{title}'", True

    async def _exec_swap(self, col, parsed, now):
        t1, t2 = parsed.get("title"), parsed.get("title2")
        if not t1 or not t2:
            return "error", "Need two event titles to swap", False

        today = now.strftime("%Y-%m-%d")
        docs1 = await _find_event(col, t1, today)
        docs2 = await _find_event(col, t2, today)

        if not docs1 or not docs2:
            missing = t1 if not docs1 else t2
            return "not_found", f"Could not find '{missing}'", False

        ref1, d1 = docs1[0]
        ref2, d2 = docs2[0]

        await ref1.update({"startTime": d2["startTime"], "endTime": d2["endTime"]})
        await ref2.update({"startTime": d1["startTime"], "endTime": d1["endTime"]})
        return "swapped", f"Swapped '{t1}' and '{t2}'", True

    async def _exec_conflict(self, col, parsed, now):
        """Find conflicting events and suggest moving the lower-priority one."""
        t1, t2 = parsed.get("title"), parsed.get("title2")
        today = now.strftime("%Y-%m-%d")
        docs1 = await _find_event(col, t1 or "", today)
        docs2 = await _find_event(col, t2 or "", today)

        if not docs1 or not docs2:
            return "not_found", "Could not find both events", False

        _, d1 = docs1[0]
        _, d2 = docs2[0]

        pri = {"low":0,"medium":1,"high":2,"critical":3}
        p1 = pri.get(d1.get("priority","medium"), 1)
        p2 = pri.get(d2.get("priority","medium"), 1)
        to_move = d1.get("title") if p1 <= p2 else d2.get("title")
        return "suggestion", (f"Suggest moving '{to_move}' — "
                             f"it has lower priority. Use 'move' command to confirm."), True

    async def _exec_bulk(self, col, parsed, now):
        target_date = parsed.get("date") or now.strftime("%Y-%m-%d")
        delay_m = parsed.get("delayMins")
        action  = parsed.get("action")
        window  = parsed.get("timeWindow")

        day = datetime.strptime(target_date, "%Y-%m-%d")
        day_end = day + timedelta(days=1)

        docs_stream = col.where("startTime", ">=", day).where("startTime", "<", day_end).stream()
        count = 0
        async for doc in docs_stream:
            d = doc.to_dict()
            if not d.get("isConfirmed", True):
                continue

            ev_start: datetime = d["startTime"]
            if window == "morning"   and not (0 <= ev_start.hour < 12): continue
            if window == "afternoon" and not (12 <= ev_start.hour < 17): continue
            if window == "evening"   and not (17 <= ev_start.hour < 22): continue

            if action == "clear":
                await doc.reference.update({"isConfirmed": False, "tags": ["bulk_cancelled"]})
            elif delay_m:
                ev_end = d["endTime"]
                await doc.reference.update({
                    "startTime": ev_start + timedelta(minutes=delay_m),
                    "endTime":   ev_end   + timedelta(minutes=delay_m),
                })
            count += 1

        verb = "cleared" if action == "clear" else f"shifted by {delay_m}min"
        return "bulk_done", f"{count} events {verb} on {target_date}", True

    async def _exec_routine(self, col, parsed, now):
        title = parsed.get("title", "")
        shift = parsed.get("shiftMins", 0)
        new_time = parsed.get("newTime")

        docs_stream = col.where("isRecurring", "==", True).stream()
        count = 0
        async for doc in docs_stream:
            d = doc.to_dict()
            if title.lower() not in d.get("title","").lower():
                continue
            ev_start: datetime = d["startTime"]
            ev_end:   datetime = d["endTime"]
            duration = ev_end - ev_start

            if new_time:
                h, m = map(int, new_time.split(":"))
                new_start = ev_start.replace(hour=h, minute=m)
            elif shift:
                new_start = ev_start + timedelta(minutes=shift)
            else:
                continue

            await doc.reference.update({
                "startTime": new_start,
                "endTime":   new_start + duration,
                "aiReason":  "Routine time updated via user command",
            })
            count += 1

        return "routine_updated", f"Updated {count} recurring '{title}' events", True


# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

async def _find_event(col, title: str, date_str: str):
    """Find events matching title on a given date."""
    try:
        day = datetime.strptime(date_str, "%Y-%m-%d")
        day_end = day + timedelta(days=1)
        docs_stream = col.where("startTime", ">=", day).where("startTime", "<", day_end).stream()
        results = []
        async for doc in docs_stream:
            d = doc.to_dict()
            if title.lower() in d.get("title", "").lower() and d.get("isConfirmed", True):
                results.append((doc.reference, d))
        return results
    except Exception:
        return []


def _guess_category(title: str) -> str:
    t = title.lower()
    if any(x in t for x in ["gym","run","yoga","exercise","workout","swim","cycle","pilates"]): return "exercise"
    if any(x in t for x in ["meeting","call","standup","sync","interview","review"]): return "meeting"
    if any(x in t for x in ["doctor","dentist","clinic","hospital","therapy"]): return "health"
    if any(x in t for x in ["travel","flight","trip"]): return "personal"
    if any(x in t for x in ["deep work","focus","study","reading","write","blog","code","samantha","traveler","phokat","gita"]): return "deepWork"
    if any(x in t for x in ["dinner","lunch","coffee","party","social"]): return "social"
    return "work"


# ═══════════════════════════════════════════════════════════════════════════════
# FASTAPI ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

_brain: Optional[SamanthaBrain] = None

def get_brain() -> SamanthaBrain:
    global _brain
    if _brain is None:
        _brain = SamanthaBrain()
    return _brain


@router.post("/command", response_model=CommandResponse)
async def process_command(req: CommandRequest):
    """
    Main endpoint. Receives a natural language command and executes it.

    Example:
        POST /brain/command
        { "command": "Move my gym to 7 PM tomorrow", "uid": "samantha_personal_user" }
    """
    brain = get_brain()
    brain.uid = req.uid or "samantha_personal_user"
    return await brain.process(req.command, req.context_time)


@router.get("/health")
async def health():
    return {"status": "ok", "module": "samantha_brain", "version": "1.0"}


# ── Run standalone for testing ─────────────────────────────────────────────────
if __name__ == "__main__":
    import asyncio

    async def demo():
        brain = SamanthaBrain()
        test_commands = [
            "Move my gym workout to 7 PM tomorrow",
            "Push my team meeting 30 minutes later",
            "Cancel my ukulele practice tonight",
            "Add a 1-hour deep work session Saturday at 9 AM",
            "Swap my gym session and standup call",
            "Clear everything on Sunday evening",
        ]
        for cmd in test_commands:
            result = await brain.process(cmd)
            print(f"\nCommand: {cmd}")
            print(f"  Intent:  {result.intent}")
            print(f"  Action:  {result.action_taken}")
            print(f"  Message: {result.message}")
            if result.conflicts:
                print(f"  Conflicts: {result.conflicts}")

    asyncio.run(demo())
