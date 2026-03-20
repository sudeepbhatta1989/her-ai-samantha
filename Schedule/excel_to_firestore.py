"""
Samantha AI — Schedule Ingestion & Modification Engine
Reads My_Schedule.xlsx → generates Firestore-ready JSON documents
Also handles chat-based schedule modification commands
"""

import json
import re
from datetime import datetime, timedelta
from pathlib import Path


# ─────────────────────────────────────────────────────────────────────────────
# 1. TIME PARSER
# ─────────────────────────────────────────────────────────────────────────────

def parse_time_range(time_str: str):
    """
    Parses strings like '5:45 – 6:15', '9:00 – 6:00', '07:00:00', '8:00 – 5:00/6:00'
    Returns (start_hour, start_min, end_hour, end_min) as ints, or None if unparseable.
    """
    if not time_str or not isinstance(time_str, str):
        return None

    # Handle datetime objects Excel sometimes returns
    time_str = str(time_str).strip()

    # Case: single time like "07:00:00" or "07:15:00"
    single = re.match(r'^(\d{1,2}):(\d{2})(?::\d{2})?$', time_str)
    if single:
        h, m = int(single.group(1)), int(single.group(2))
        return h, m, h, m  # point-in-time, no duration

    # Case: range like "5:45 – 6:15" or "8:00 - 9:00" or "8:00 – 5:00/6:00"
    # normalize dash variants
    time_str = time_str.replace('–', '-').replace('—', '-')
    # take first option if "5:00/6:00"
    time_str = re.sub(r'(\d+:\d+)/\d+:\d+', r'\1', time_str)

    rng = re.match(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})', time_str)
    if rng:
        sh, sm = int(rng.group(1)), int(rng.group(2))
        eh, em = int(rng.group(3)), int(rng.group(4))
        # handle PM wrap: if office is "9:00 – 6:00", end 6 means 18:00
        if eh < sh and eh < 12:
            eh += 12
        # Fix minute overflow (e.g. 8:30 + 30min = 9:00, not 8:60)
        if em >= 60:
            eh += em // 60
            em = em % 60
        return sh, sm, eh, em

    return None


def to_iso(year: int, month: int, day: int, hour: int, minute: int) -> str:
    """Returns ISO 8601 string for a given local datetime."""
    return datetime(year, month, day, hour, minute).isoformat()


# ─────────────────────────────────────────────────────────────────────────────
# 2. CATEGORY & PRIORITY MAPPING  (from your task spec)
# ─────────────────────────────────────────────────────────────────────────────

CATEGORY_MAP = {
    "exercise": "exercise",
    "running": "exercise",
    "pencil sketch": "personal",
    "sketch": "personal",
    "ukulele": "personal",
    "phokat ka gyan": "deepWork",
    "debate video": "deepWork",
    "traveler tree": "deepWork",
    "sapna canvas": "work",
    "office": "work",
    "work": "work",
    "gita app": "deepWork",
    "samantha": "deepWork",
    "content": "work",
    "short": "work",
    "reel": "work",
    "batch record": "work",
    "publish": "work",
    "editing": "work",
    "plan": "work",
    "morning routine": "personal",
    "bathroom": "personal",
    "get dressed": "personal",
    "breakfast": "personal",
    "dinner": "personal",
    "rest": "personal",
    "bus": "general",
    "reach home": "general",
    "game development": "deepWork",
    "learning": "deepWork",
    "blogs": "deepWork",
    "marketing": "work",
    "website": "deepWork",
}

PRIORITY_MAP = {
    "office": "critical",
    "work": "critical",
    "corporate kurukshetra": "critical",
    "publish": "critical",
    "exercise": "high",
    "running": "high",
    "traveler tree": "medium",
    "sapna canvas": "medium",
    "phokat ka gyan": "medium",
    "gita app": "medium",
    "samantha": "medium",
    "pencil sketch": "medium",
    "sketch": "medium",
    "ukulele": "medium",
    "game development": "medium",
    "learning": "medium",
    "debate video": "medium",
    "blogs": "medium",
    "marketing": "medium",
    "dinner": "low",
    "breakfast": "low",
    "rest": "low",
    "morning routine": "low",
    "bathroom": "low",
    "get dressed": "low",
    "bus": "low",
    "reach home": "low",
    "plan": "low",
}

TAGS_MAP = {
    "corporate kurukshetra": ["phokatkagyan", "content"],
    "debate video": ["phokatkagyan", "video"],
    "short": ["phokatkagyan", "content"],
    "reel": ["phokatkagyan", "content"],
    "traveler tree": ["travelertree"],
    "sapna canvas": ["sapnacanvas"],
    "gita app": ["gitaapp"],
    "samantha": ["samanthaai"],
    "phokat ka gyan": ["phokatkagyan"],
    "exercise": ["health", "fitness"],
    "ukulele": ["music", "creative"],
    "pencil sketch": ["art", "creative"],
    "sketch": ["art", "creative"],
}


def classify(title: str):
    t = title.lower()
    category = "general"
    priority = "medium"
    tags = []

    for key, val in CATEGORY_MAP.items():
        if key in t:
            category = val
            break

    for key, val in PRIORITY_MAP.items():
        if key in t:
            priority = val
            break

    for key, val in TAGS_MAP.items():
        if key in t:
            tags = val
            break

    return category, priority, tags


# ─────────────────────────────────────────────────────────────────────────────
# 3. RECURRING RULE DETECTOR
# ─────────────────────────────────────────────────────────────────────────────

RECURRING_RULES = {
    # title_fragment → (isRecurring, recurringRule)
    "exercise":            (True, "daily"),
    "running":             (True, "daily"),
    "ukulele":             (True, "daily"),
    "pencil sketch":       (True, "daily"),
    "sketch":              (True, "daily"),
    "office work":         (True, "weekdays"),
    "bus from":            (True, "weekdays"),
    "reach home":          (True, "weekdays"),
    "breakfast":           (True, "daily"),
    "bathroom":            (True, "daily"),
    "get dressed":         (True, "daily"),
    "dinner":              (True, "daily"),
    "corporate kurukshetra published": (True, "weekly"),
    "corporate kurukshetra prep":      (True, "weekly"),
    "prepare next day short":          (True, "weekdays"),
    "prepare short":                   (True, "weekdays"),
    "batch record":                    (True, "weekly"),
    "plan next week":                  (True, "weekly"),
    "debate video":                    (True, "weekly"),
    "youtube short + instagram reel published": (True, "weekdays"),
}


def get_recurring(title: str):
    t = title.lower()
    for key, (is_rec, rule) in RECURRING_RULES.items():
        if key in t:
            return is_rec, rule
    return False, None


# ─────────────────────────────────────────────────────────────────────────────
# 4. EXCEL PARSER → STRUCTURED EVENTS
# ─────────────────────────────────────────────────────────────────────────────

# Day context: what weekday does each section belong to?
# We'll store as (day_name, is_wfh)
DAY_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

# Map day name to ISO weekday (Monday=0)
DAY_WEEKDAY = {d: i for i, d in enumerate(DAY_ORDER)}


def parse_excel(filepath: str) -> list[dict]:
    """
    Reads the Excel file and returns a list of raw event dicts.
    """
    import openpyxl
    wb = openpyxl.load_workbook(filepath)
    ws = wb.active

    events = []
    current_day = "Monday"
    current_section = "morning"  # morning | evening | wfh
    is_wfh = False

    for row in ws.iter_rows(values_only=True):
        time_val = str(row[0]).strip() if row[0] else ""
        activity = str(row[1]).strip() if row[1] else ""

        if not time_val and not activity:
            continue

        # Section headers
        combined = (time_val + " " + activity).strip()

        if "Monday–Friday Morning Routine" in combined or "Monday-Friday Morning Routine" in combined:
            current_day = "Weekday"
            current_section = "morning"
            is_wfh = False
            continue

        if "If Work From Home" in combined or "Work From Home" in combined:
            current_section = "wfh"
            is_wfh = True
            continue

        for day in DAY_ORDER:
            if combined.startswith(day) and ("Evening" in combined or "Day" in combined or combined == day):
                current_day = day
                current_section = "evening"
                is_wfh = False
                break

        # Skip header rows (Time/Activity/Task)
        if time_val.lower() in ("time", "") and activity.lower() in ("activity", "task", ""):
            continue

        # Parse time
        parsed = parse_time_range(time_val)
        if not parsed:
            continue
        sh, sm, eh, em = parsed

        # Skip point-in-time non-events (single timestamps that are transitions)
        # Keep them only if they have meaningful activity titles
        if sh == eh and sm == em:
            # assign a duration based on context
            # e.g. "Bus from Sector 28 Metro" → 90 min commute
            if "bus" in activity.lower():
                eh, em = sh + 1, sm + 30
            elif "reach home" in activity.lower():
                eh, em = sh, sm + 15
            elif "published" in activity.lower() or "reel" in activity.lower():
                eh, em = sh, sm + 30
            elif "kurukshetra published" in activity.lower():
                eh, em = sh, sm + 15
            else:
                eh, em = sh, sm + 30  # default 30 min
            if em >= 60:
                eh += em // 60
                em = em % 60

        category, priority, tags = classify(activity)
        is_rec, rec_rule = get_recurring(activity)

        events.append({
            "title": activity,
            "day": current_day,
            "section": current_section,
            "is_wfh": is_wfh,
            "startHour": sh, "startMin": sm,
            "endHour": eh, "endMin": em,
            "category": category,
            "priority": priority,
            "tags": tags,
            "isRecurring": is_rec,
            "recurringRule": rec_rule,
        })

    return events


# ─────────────────────────────────────────────────────────────────────────────
# 5. CONVERT TO FIRESTORE DOCUMENTS
#    Uses the NEXT occurrence of each day as the anchor date
# ─────────────────────────────────────────────────────────────────────────────

def next_weekday_date(target_weekday: int, from_date: datetime = None) -> datetime:
    """Returns the next occurrence of a given weekday (0=Monday)."""
    today = from_date or datetime.now()
    days_ahead = target_weekday - today.weekday()
    if days_ahead <= 0:
        days_ahead += 7
    return today + timedelta(days=days_ahead)


def events_to_firestore(raw_events: list[dict]) -> list[dict]:
    """
    Converts raw event dicts into Firestore document dicts.
    For recurring events, uses the next occurrence as the anchor date.
    """
    docs = []
    today = datetime.now()

    for ev in raw_events:
        day_name = ev["day"]

        # Determine anchor date
        if day_name == "Weekday":
            # Use Monday as canonical weekday anchor
            anchor = next_weekday_date(0, today)
        elif day_name in DAY_WEEKDAY:
            anchor = next_weekday_date(DAY_WEEKDAY[day_name], today)
        else:
            anchor = today

        start = datetime(anchor.year, anchor.month, anchor.day,
                         ev["startHour"], ev["startMin"])
        end = datetime(anchor.year, anchor.month, anchor.day,
                       ev["endHour"], ev["endMin"])

        # Safety: if end < start (crosses midnight)
        if end < start:
            end += timedelta(days=1)

        doc = {
            "title": ev["title"],
            "description": None,
            "startTime": start.isoformat(),    # Store as ISO; app converts to Timestamp
            "endTime": end.isoformat(),
            "priority": ev["priority"],
            "category": ev["category"],
            "source": "samantha",
            "tags": ev["tags"],
            "isRecurring": ev["isRecurring"],
            "recurringRule": ev["recurringRule"],
            "aiGenerated": True,
            "aiReason": "Generated from user's weekly template schedule",
            "isConfirmed": True,
            # metadata
            "_dayContext": ev["day"],
            "_section": ev["section"],
            "_isWFH": ev["is_wfh"],
        }
        docs.append(doc)

    return docs


# ─────────────────────────────────────────────────────────────────────────────
# 6. CONFLICT DETECTION
# ─────────────────────────────────────────────────────────────────────────────

def detect_conflicts(docs: list[dict]) -> list[dict]:
    """
    Returns list of conflict pairs from the generated documents.
    Two events conflict if they share the same day AND overlap in time.
    """
    conflicts = []
    for i in range(len(docs)):
        for j in range(i + 1, len(docs)):
            a, b = docs[i], docs[j]
            a_start = datetime.fromisoformat(a["startTime"])
            a_end = datetime.fromisoformat(a["endTime"])
            b_start = datetime.fromisoformat(b["startTime"])
            b_end = datetime.fromisoformat(b["endTime"])

            if a_start.date() != b_start.date():
                continue

            if a_start < b_end and a_end > b_start:
                overlap_start = max(a_start, b_start)
                overlap_end = min(a_end, b_end)
                conflicts.append({
                    "event_a": a["title"],
                    "event_b": b["title"],
                    "date": a_start.date().isoformat(),
                    "overlap_minutes": int((overlap_end - overlap_start).total_seconds() / 60),
                })
    return conflicts


# ─────────────────────────────────────────────────────────────────────────────
# 7. COMMAND PARSER  (chat → JSON action)
# ─────────────────────────────────────────────────────────────────────────────

TIME_PATTERNS = [
    (r'(\d{1,2}):(\d{2})\s*(am|pm)?', lambda m: _to24(int(m.group(1)), int(m.group(2)), m.group(3))),
    (r'(\d{1,2})\s*(am|pm)',           lambda m: _to24(int(m.group(1)), 0, m.group(2))),
    (r'\b(morning)\b',   lambda m: "07:00"),
    (r'\b(afternoon)\b', lambda m: "14:00"),
    (r'\b(evening)\b',   lambda m: "19:00"),
    (r'\b(night)\b',     lambda m: "21:00"),
]

DATE_PATTERNS = [
    (r'\btoday\b',     "today"),
    (r'\btomorrow\b',  "tomorrow"),
    (r'\bmonday\b',    "monday"),
    (r'\btuesday\b',   "tuesday"),
    (r'\bwednesday\b', "wednesday"),
    (r'\bthursday\b',  "thursday"),
    (r'\bfriday\b',    "friday"),
    (r'\bsaturday\b',  "saturday"),
    (r'\bsunday\b',    "sunday"),
]

DURATION_PATTERN = r'for\s+(\d+(?:\.\d+)?)\s*(hour|hr|h|minute|min|m)s?'

KNOWN_EVENTS = [
    "exercise", "running", "ukulele", "pencil sketch", "sketch",
    "office", "work", "traveler tree", "sapna canvas", "phokat ka gyan",
    "corporate kurukshetra", "debate video", "gita app", "samantha",
    "breakfast", "dinner", "morning routine", "short", "reel",
    "batch record", "plan", "editing", "blogs",
]


def _to24(h: int, m: int, meridiem: str | None) -> str:
    if meridiem:
        meridiem = meridiem.lower()
        if meridiem == "pm" and h != 12:
            h += 12
        elif meridiem == "am" and h == 12:
            h = 0
    return f"{h:02d}:{m:02d}"


def extract_time(text: str) -> str | None:
    t = text.lower()
    for pattern, converter in TIME_PATTERNS:
        m = re.search(pattern, t)
        if m:
            result = converter(m)
            return result
    return None


def extract_date(text: str) -> str | None:
    t = text.lower()
    for pattern, label in DATE_PATTERNS:
        if re.search(pattern, t):
            return label
    return None


def extract_duration_minutes(text: str) -> int | None:
    t = text.lower()
    m = re.search(DURATION_PATTERN, t)
    if m:
        val = float(m.group(1))
        unit = m.group(2)
        if unit.startswith("h"):
            return int(val * 60)
        else:
            return int(val)
    return None


def extract_event_title(text: str) -> str | None:
    t = text.lower()
    for ev in sorted(KNOWN_EVENTS, key=len, reverse=True):
        if ev in t:
            return ev.title()
    return None


def parse_command(user_input: str) -> dict:
    """
    Parses natural language schedule commands into structured JSON actions.

    Supported intents:
      add_event    → "Add TravelerTree work tomorrow 8 PM for 2 hours"
      modify_event → "Move exercise today to 7 PM"
      delete_event → "Cancel ukulele practice today"
      query        → "What's on my schedule today?"
    """
    text = user_input.strip()
    t = text.lower()

    # ── Determine intent ──────────────────────────────────────────────────────
    if any(kw in t for kw in ["add", "schedule", "book", "create", "set"]):
        intent = "add_event"
    elif any(kw in t for kw in ["move", "shift", "change", "reschedule", "update", "modify"]):
        intent = "modify_event"
    elif any(kw in t for kw in ["cancel", "delete", "remove", "skip"]):
        intent = "delete_event"
    elif any(kw in t for kw in ["what", "show", "list", "any conflicts", "check"]):
        intent = "query"
    else:
        intent = "unknown"

    action = {"intent": intent, "raw_input": text}

    title = extract_event_title(text)
    if title:
        action["title"] = title

    date = extract_date(text)
    if date:
        action["date"] = date

    time_val = extract_time(text)
    if time_val:
        if intent == "modify_event":
            action["newStartTime"] = time_val
        elif intent == "add_event":
            action["startTime"] = time_val

    duration = extract_duration_minutes(text)
    if duration:
        action["durationMinutes"] = duration

    # ── Handle "query" ────────────────────────────────────────────────────────
    if intent == "query":
        if "conflict" in t:
            action["queryType"] = "conflicts"
        elif "free" in t or "available" in t:
            action["queryType"] = "free_slots"
        else:
            action["queryType"] = "summary"

    return action


# ─────────────────────────────────────────────────────────────────────────────
# 8. EVENT MODIFICATION LOGIC  (returns patched Firestore doc)
# ─────────────────────────────────────────────────────────────────────────────

def apply_modification(doc: dict, action: dict) -> dict:
    """
    Applies a parsed modify_event action to an existing Firestore doc.
    Returns the updated doc.
    """
    updated = doc.copy()

    if action.get("newStartTime"):
        h, m = map(int, action["newStartTime"].split(":"))
        old_start = datetime.fromisoformat(doc["startTime"])
        old_end   = datetime.fromisoformat(doc["endTime"])
        duration  = old_end - old_start

        new_start = old_start.replace(hour=h, minute=m)
        new_end   = new_start + duration

        updated["startTime"] = new_start.isoformat()
        updated["endTime"]   = new_end.isoformat()

    if action.get("newEndTime"):
        h, m = map(int, action["newEndTime"].split(":"))
        old_end = datetime.fromisoformat(doc["endTime"])
        updated["endTime"] = old_end.replace(hour=h, minute=m).isoformat()

    # Tag as modified
    tags = list(updated.get("tags") or [])
    if "modified_by_user" not in tags:
        tags.append("modified_by_user")
    updated["tags"] = tags
    updated["aiReason"] = "Modified based on user request"

    return updated


def apply_deletion(doc: dict) -> dict:
    """Soft-deletes an event (isConfirmed=False, tags=['cancelled'])."""
    updated = doc.copy()
    updated["isConfirmed"] = False
    tags = list(updated.get("tags") or [])
    if "cancelled" not in tags:
        tags.append("cancelled")
    updated["tags"] = tags
    updated["aiReason"] = "Cancelled by user request"
    return updated


def create_new_event(action: dict, date_anchor: datetime = None) -> dict:
    """Builds a new Firestore document from an add_event action."""
    anchor = date_anchor or datetime.now()
    title = action.get("title", "New Event")
    start_time_str = action.get("startTime", "09:00")
    h, m = map(int, start_time_str.split(":"))
    duration = action.get("durationMinutes", 60)

    start = anchor.replace(hour=h, minute=m, second=0, microsecond=0)
    end   = start + timedelta(minutes=duration)

    category, priority, tags = classify(title)
    is_rec, rec_rule = get_recurring(title)

    return {
        "title": title,
        "description": None,
        "startTime": start.isoformat(),
        "endTime": end.isoformat(),
        "priority": priority,
        "category": category,
        "source": "samantha",
        "tags": tags,
        "isRecurring": is_rec,
        "recurringRule": rec_rule,
        "aiGenerated": True,
        "aiReason": "User requested new activity",
        "isConfirmed": True,
    }


def check_conflict_for_new_event(new_doc: dict, existing_docs: list[dict]) -> list[dict]:
    """
    Checks if a new event conflicts with existing events on the same day.
    Returns list of conflicting docs.
    """
    conflicts = []
    ns = datetime.fromisoformat(new_doc["startTime"])
    ne = datetime.fromisoformat(new_doc["endTime"])

    for doc in existing_docs:
        if not doc.get("isConfirmed", True):
            continue
        es = datetime.fromisoformat(doc["startTime"])
        ee = datetime.fromisoformat(doc["endTime"])
        if es.date() != ns.date():
            continue
        if ns < ee and ne > es:
            conflicts.append(doc)

    return conflicts


def suggest_alternative_times(new_doc: dict, existing_docs: list[dict]) -> list[str]:
    """Returns up to 3 free time slots on the same day for the event's duration."""
    ns = datetime.fromisoformat(new_doc["startTime"])
    duration = (datetime.fromisoformat(new_doc["endTime"]) -
                datetime.fromisoformat(new_doc["startTime"]))
    day = ns.date()

    busy = []
    for doc in existing_docs:
        if not doc.get("isConfirmed", True):
            continue
        ds = datetime.fromisoformat(doc["startTime"])
        de = datetime.fromisoformat(doc["endTime"])
        if ds.date() == day:
            busy.append((ds, de))
    busy.sort()

    suggestions = []
    candidate = datetime(day.year, day.month, day.day, 8, 0)
    while candidate.hour < 21 and len(suggestions) < 3:
        cand_end = candidate + duration
        if cand_end.hour > 22:
            break
        overlap = any(s < cand_end and e > candidate for s, e in busy)
        if not overlap:
            suggestions.append(candidate.strftime("%I:%M %p"))
        candidate += timedelta(minutes=30)

    return suggestions


# ─────────────────────────────────────────────────────────────────────────────
# 9. MAIN — Run the full pipeline
# ─────────────────────────────────────────────────────────────────────────────

def run_pipeline(xlsx_path: str, output_path: str):
    print("=" * 60)
    print("  SAMANTHA SCHEDULE INGESTION PIPELINE")
    print("=" * 60)

    # Step 1: Parse Excel
    print("\n[1/4] Parsing Excel file...")
    raw = parse_excel(xlsx_path)
    print(f"      Found {len(raw)} activities")

    # Step 2: Convert to Firestore docs
    print("[2/4] Converting to Firestore documents...")
    docs = events_to_firestore(raw)
    print(f"      Generated {len(docs)} documents")

    # Step 3: Detect conflicts in template schedule
    print("[3/4] Checking for conflicts...")
    conflicts = detect_conflicts(docs)
    if conflicts:
        print(f"      ⚠  {len(conflicts)} conflicts found:")
        for c in conflicts[:5]:
            print(f"      • '{c['event_a']}' vs '{c['event_b']}' "
                  f"on {c['date']} ({c['overlap_minutes']} min overlap)")
    else:
        print("      ✅ No conflicts")

    # Step 4: Save output
    print("[4/4] Saving output JSON...")
    output = {
        "firestore_collection": "users/{uid}/schedule",
        "total_events": len(docs),
        "conflicts_detected": len(conflicts),
        "events": docs,
        "conflicts": conflicts,
    }
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, default=str)
    print(f"      Saved to: {output_path}")

    print("\n" + "=" * 60)
    print(f"  DONE — {len(docs)} events ready for Firestore")
    print("=" * 60)

    return docs, conflicts


if __name__ == "__main__":
    xlsx = "/mnt/user-data/uploads/My_Schedule.xlsx"
    out  = "/home/claude/samantha_schedule/schedule_firestore.json"
    Path("/home/claude/samantha_schedule").mkdir(parents=True, exist_ok=True)
    run_pipeline(xlsx, out)

    # Demo: test the command parser
    print("\n── COMMAND PARSER DEMO ──────────────────────────────────")
    test_commands = [
        "Move exercise today to 7 PM",
        "Add TravelerTree work tomorrow 8 PM for 2 hours",
        "Cancel ukulele practice today",
        "What conflicts do I have today?",
        "Reschedule office work to morning",
        "Add Samantha AI development Saturday 9 AM for 3 hours",
    ]
    for cmd in test_commands:
        result = parse_command(cmd)
        print(f"\nInput:  {cmd}")
        print(f"Parsed: {json.dumps(result, indent=2)}")
