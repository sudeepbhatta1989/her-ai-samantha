# backend/schedule_api.py
# Add to your existing FastAPI app:
#   from schedule_api import router as schedule_router
#   app.include_router(schedule_router)
#
# Requirements (add to requirements.txt):
#   groq>=0.5.0
#   python-dateutil>=2.8.0
#
# Env vars needed:
#   GROQ_API_KEY=your_key_here  (free at console.groq.com)

import os
import re
import json
from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from groq import Groq

router = APIRouter(prefix="/schedule", tags=["schedule"])
_groq: Optional[Groq] = None

def get_groq() -> Optional[Groq]:
    global _groq
    if _groq is None and os.getenv("GROQ_API_KEY"):
        _groq = Groq(api_key=os.getenv("GROQ_API_KEY"))
    return _groq


# ── REQUEST / RESPONSE MODELS ─────────────────────────────────────────────

class EventItem(BaseModel):
    title: str
    start: str
    end: str
    category: str = "general"
    priority: str = "medium"
    source: str = "samantha"

class BriefingRequest(BaseModel):
    date: str
    events: list[EventItem]
    conflicts: int = 0

class BriefingResponse(BaseModel):
    summary: str
    insights: list[str]
    energy_advice: str
    focus_windows: list[str]

class ParseRequest(BaseModel):
    input: str
    context_date: str

class ParsedEvent(BaseModel):
    action: str           # create | query | reschedule | delete | unknown
    event: Optional[dict] = None
    message: str = ""

class ConflictRequest(BaseModel):
    event_a: EventItem
    event_b: EventItem
    all_events: list[EventItem] = []

class ConflictResponse(BaseModel):
    suggestions: list[dict]
    explanation: str


# ── ENDPOINTS ─────────────────────────────────────────────────────────────

@router.post("/briefing", response_model=BriefingResponse)
async def get_briefing(req: BriefingRequest):
    """
    AI-powered daily briefing using Groq llama-3.1-70b.
    Falls back to rule-based generation if Groq is unavailable.
    """
    if not req.events:
        return BriefingResponse(
            summary="Your day is clear — ideal for deep work or planning ahead.",
            insights=["✨ No events scheduled today"],
            energy_advice="Use the unstructured time for your most cognitively demanding work.",
            focus_windows=["All day available for focus work"]
        )

    groq = get_groq()
    if groq:
        return await _groq_briefing(groq, req)
    return _rule_based_briefing(req)


@router.post("/parse", response_model=ParsedEvent)
async def parse_natural_language(req: ParseRequest):
    """
    Convert natural language schedule requests to structured actions.
    e.g. "Add a team meeting tomorrow at 10am for 1 hour"
    """
    groq = get_groq()
    if not groq:
        return ParsedEvent(action="unknown", message="NL parsing requires GROQ_API_KEY")

    system = """You are a schedule assistant. Parse the user's request and respond with ONLY valid JSON:
{
  "action": "create|query|reschedule|delete|unknown",
  "event": {
    "title": "string",
    "date": "YYYY-MM-DD",
    "start_time": "HH:MM",
    "end_time": "HH:MM",
    "category": "meeting|work|health|personal|exercise|social|general",
    "priority": "low|medium|high|critical"
  },
  "message": "brief confirmation string"
}
For query/reschedule/delete actions, set event to null.
Today's date context: """ + req.context_date

    try:
        resp = groq.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": req.input}
            ],
            max_tokens=300,
            temperature=0.1,
        )
        raw = resp.choices[0].message.content.strip()
        # Strip markdown code fences if present
        raw = re.sub(r"```(?:json)?", "", raw).strip("` \n")
        data = json.loads(raw)
        return ParsedEvent(
            action=data.get("action", "unknown"),
            event=data.get("event"),
            message=data.get("message", "")
        )
    except Exception as e:
        return ParsedEvent(action="unknown", message=f"Parse error: {str(e)}")


@router.post("/resolve-conflict", response_model=ConflictResponse)
async def resolve_conflict(req: ConflictRequest):
    """
    Given two conflicting events + context, suggest reschedule options.
    """
    a_start = datetime.fromisoformat(req.event_a.start)
    a_end   = datetime.fromisoformat(req.event_a.end)
    b_start = datetime.fromisoformat(req.event_b.start)
    b_end   = datetime.fromisoformat(req.event_b.end)

    # Build busy windows from all events
    busy: list[tuple[datetime, datetime]] = []
    for e in req.all_events:
        try:
            busy.append((datetime.fromisoformat(e.start), datetime.fromisoformat(e.end)))
        except Exception:
            pass

    # Decide which event to move (lower priority index = higher priority, keep it)
    priority_map = {"critical": 4, "high": 3, "medium": 2, "low": 1}
    pa = priority_map.get(req.event_a.priority, 2)
    pb = priority_map.get(req.event_b.priority, 2)
    if pa >= pb:
        to_move, to_move_dur = req.event_b, b_end - b_start
    else:
        to_move, to_move_dur = req.event_a, a_end - a_start

    # Find free slots
    base_day = a_start.replace(hour=8, minute=0, second=0, microsecond=0)
    slots = _find_free_slots(busy, base_day, to_move_dur, count=3)

    suggestions = [
        {
            "event_id": to_move.title,
            "new_start": s.isoformat(),
            "new_end": (s + to_move_dur).isoformat(),
            "reason": _slot_reason(s),
        }
        for s in slots
    ]

    groq = get_groq()
    explanation = f"'{to_move.title}' has lower priority — moving it frees up the conflict."
    if groq:
        try:
            resp = groq.chat.completions.create(
                model="llama-3.1-8b-instant",
                messages=[{"role": "user", "content":
                    f"'{req.event_a.title}' and '{req.event_b.title}' overlap. "
                    f"Explain in one sentence why moving '{to_move.title}' makes sense for productivity."}],
                max_tokens=80, temperature=0.3,
            )
            explanation = resp.choices[0].message.content.strip()
        except Exception:
            pass

    return ConflictResponse(suggestions=suggestions, explanation=explanation)


@router.post("/suggestions")
async def get_suggestions(events: list[EventItem], date: str):
    """
    Proactive scheduling suggestions: detect heavy days, missing breaks, etc.
    """
    insights = []
    meeting_count = sum(1 for e in events if e.category == "meeting")
    if meeting_count >= 4:
        insights.append({
            "type": "heavy_meeting_day",
            "message": f"{meeting_count} meetings scheduled — consider blocking 15-min breaks between them.",
            "icon": "⚠️"
        })

    # Check for missing lunch window
    lunch_events = [e for e in events if _time_in_window(e.start, 12, 14)]
    if lunch_events:
        insights.append({
            "type": "no_lunch_break",
            "message": "Your lunch window is occupied — you might want to protect some downtime.",
            "icon": "🍽️"
        })

    # Suggest deep work block if early morning is free
    early_free = all(not _time_in_window(e.start, 8, 10) for e in events)
    if early_free and events:
        insights.append({
            "type": "focus_opportunity",
            "message": "Your morning is free — great time to block 2h for deep work.",
            "icon": "🧠"
        })

    return {"insights": insights, "date": date}


# ── HELPERS ───────────────────────────────────────────────────────────────

async def _groq_briefing(groq: Groq, req: BriefingRequest) -> BriefingResponse:
    event_list = "\n".join(
        f"- {e.title} [{e.category}, {e.priority}] from {e.start[11:16]} to {e.end[11:16]}"
        for e in req.events
    )
    source_note = ""
    google_n = sum(1 for e in req.events if e.source == "googleCalendar")
    apple_n  = sum(1 for e in req.events if e.source == "appleCalendar")
    if google_n or apple_n:
        parts = []
        if google_n: parts.append(f"{google_n} from Google Calendar")
        if apple_n:  parts.append(f"{apple_n} from Apple Calendar")
        source_note = f"\n(Synced events: {', '.join(parts)})"

    prompt = f"""You are Samantha, a warm and perceptive AI assistant. Generate a concise daily briefing.

Date: {req.date[:10]}
Events:{source_note}
{event_list}
Conflicts detected: {req.conflicts}

Respond ONLY with valid JSON (no markdown):
{{
  "summary": "2-3 sentence natural briefing",
  "insights": ["insight 1", "insight 2"],
  "energy_advice": "one sentence energy/focus tip",
  "focus_windows": ["time window description"]
}}"""

    try:
        resp = groq.chat.completions.create(
            model="llama-3.1-70b-versatile",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=400,
            temperature=0.4,
        )
        raw = resp.choices[0].message.content.strip()
        raw = re.sub(r"```(?:json)?", "", raw).strip("` \n")
        data = json.loads(raw)
        return BriefingResponse(
            summary=data.get("summary", _rule_based_briefing(req).summary),
            insights=data.get("insights", []),
            energy_advice=data.get("energy_advice", ""),
            focus_windows=data.get("focus_windows", []),
        )
    except Exception:
        return _rule_based_briefing(req)


def _rule_based_briefing(req: BriefingRequest) -> BriefingResponse:
    n = len(req.events)
    high = sum(1 for e in req.events if e.priority in ("high", "critical"))
    meetings = sum(1 for e in req.events if e.category == "meeting")
    google_n = sum(1 for e in req.events if e.source == "googleCalendar")
    apple_n  = sum(1 for e in req.events if e.source == "appleCalendar")

    summary = f"You have {n} event{'s' if n > 1 else ''} today"
    if high: summary += f", including {high} high-priority item{'s' if high > 1 else ''}"
    if req.conflicts: summary += f". ⚠️ {req.conflicts} conflict{'s' if req.conflicts > 1 else ''} need{'s' if req.conflicts == 1 else ''} your attention"
    summary += "."

    insights = []
    if meetings >= 3:
        insights.append(f"🤝 Heavy meeting day ({meetings} meetings) — protect recovery time between calls")
    if high >= 2:
        insights.append(f"🔥 {high} high-priority items — tackle these when your energy is highest")
    if google_n: insights.append(f"📅 {google_n} event{'s' if google_n > 1 else ''} synced from Google Calendar")
    if apple_n:  insights.append(f"🍎 {apple_n} event{'s' if apple_n > 1 else ''} synced from Apple Calendar")
    if not insights:
        insights.append("✅ Schedule is clear of major issues")

    energy = "Stay hydrated and take short breaks between tasks to maintain focus throughout the day."
    if n <= 2:
        energy = "Light day — ideal for strategic thinking or tackling your most complex project."
    elif meetings >= 4:
        energy = "Heavy social day — schedule 10-min recovery windows between meetings."

    return BriefingResponse(
        summary=summary, insights=insights,
        energy_advice=energy, focus_windows=[]
    )


def _find_free_slots(
    busy: list[tuple[datetime, datetime]],
    base: datetime,
    duration: timedelta,
    count: int = 3
) -> list[datetime]:
    slots = []
    candidate = base
    while candidate.hour < 20 and len(slots) < count:
        cand_end = candidate + duration
        overlap = any(s < cand_end and e > candidate for s, e in busy)
        if not overlap:
            slots.append(candidate)
        candidate += timedelta(minutes=30)
    return slots


def _slot_reason(t: datetime) -> str:
    h = t.hour
    if h < 10:  return "Early morning — peak cognitive focus"
    if h < 12:  return "Mid-morning — high energy window"
    if h < 14:  return "Pre-lunch — still sharp"
    if h < 17:  return "Afternoon — steady productivity"
    return "Evening — wind-down window"


def _time_in_window(iso: str, start_h: int, end_h: int) -> bool:
    try:
        h = datetime.fromisoformat(iso).hour
        return start_h <= h < end_h
    except Exception:
        return False
