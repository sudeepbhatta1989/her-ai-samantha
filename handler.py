import json, os, requests, datetime, concurrent.futures, threading
from firebase_admin import credentials, firestore, initialize_app
import firebase_admin

GROQ_API_KEY = os.environ.get('GROQ_API_KEY', '')
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
SERPER_API_KEY = os.environ.get('SERPER_API_KEY', '')  # Free: 2500 searches, no card needed

# ─────────────────────────────────────────
# WEB SEARCH (Serper.dev - Google Search API)
# ─────────────────────────────────────────
def web_search(query, num_results=3):
    """Search Google via Serper.dev (free: 2500 queries, no credit card)"""
    if not SERPER_API_KEY:
        return None
    try:
        response = requests.post(
            'https://google.serper.dev/search',
            headers={'X-API-KEY': SERPER_API_KEY, 'Content-Type': 'application/json'},
            json={'q': query, 'num': num_results, 'gl': 'in', 'hl': 'en'},
            timeout=8
        )
        if response.status_code == 200:
            data = response.json()
            snippets = []
            kg = data.get('knowledgeGraph', {})
            if kg.get('description'):
                snippets.append(f"- {kg.get('title','')}: {kg.get('description','')}")
            for r in data.get('organic', [])[:num_results]:
                snippets.append(f"- {r.get('title','')}: {r.get('snippet','')}")
            return '\n'.join(snippets) if snippets else None
    except Exception as e:
        print(f'Web search error: {e}')
    return None

def needs_web_search(message):
    """Detect if user wants web/internet info OR asks about something that needs current data"""
    explicit_triggers = [
        'search', 'look up', 'find out', 'check online', 'internet', 'web',
        'google', 'find me', 'latest news', 'update on', 'status of',
        'trending', 'whats happening', "what's happening", 'check internet',
        'check the internet', 'search the internet', 'look it up',
        'oscar', 'oscars', 'award', 'winner', 'nomination',
    ]
    # Topics that always need fresh data
    realtime_triggers = [
        'weather', 'temperature', 'news tonight', 'news today',
        'price', 'rate', 'stock', 'score', 'match', 'election', 'launch',
        'release', 'new movie', 'new film', 'trailer', 'box office',
        'current news', 'recent news', 'latest news', 'right now',
        'breaking news', 'headlines',
    ]
    # Questions about specific named things that might be new/unknown
    knowledge_gap_triggers = [
        'who is', 'what is', 'tell me about', 'batao', 'kya hai', 'kaun hai',
        'movie', 'film', 'show', 'series', 'web series', 'song', 'album',
        'app', 'startup', 'company', 'event', 'festival',
    ]
    msg_lower = message.lower()
    if any(t in msg_lower for t in explicit_triggers):
        return True
    if any(t in msg_lower for t in realtime_triggers):
        return True
    # For knowledge gap triggers, only search if message is a question
    if any(t in msg_lower for t in knowledge_gap_triggers):
        if '?' in message or any(q in msg_lower for q in ['kya', 'kaun', 'what', 'who', 'which', 'how', 'when', 'where', 'tell', 'batao', 'bata']):
            return True
    return False


def needs_reschedule(message):
    """Detect if user wants to reschedule/regenerate today's plan"""
    triggers = [
        'reschedule', 're-schedule', 'update my plan', 'change my plan',
        'update plan', 'new plan', 'regenerate plan', 'redo my plan',
        'woke up late', 'woke up now', 'just woke', 'i woke up',
        'just woke up', 'late start', 'started late', 'missed morning',
        'missed my morning', 'havent done anything', "haven't done anything",
        'didnt do anything', "didn't do anything", 'nothing done yet',
        'havent started', "haven't started", 'adjust my schedule',
        'adjust schedule', 'push my tasks', 'shift my tasks',
        'today ka plan', 'aaj ka plan', 'plan badlo', 'plan update karo',
    ]
    msg_lower = message.lower()
    # Must be about today/schedule + have reschedule signal
    has_today = any(t in msg_lower for t in ['today', 'aaj', 'schedule', 'plan', 'activities', 'tasks'])
    has_reschedule = any(t in msg_lower for t in triggers)
    return has_reschedule or (has_today and any(t in msg_lower for t in ['woke', 'woken', 'just woke', 'late', 'missed', 'nothing', 'havent', "haven't", 'didnt', "didn't"]))

# ─────────────────────────────────────────
# FIREBASE INIT
# ─────────────────────────────────────────
_firebase_ok = None  # None=untested, True=ok, False=broken
_firebase_lock = threading.Lock()

def _test_firestore_connection():
    """Probe Firestore with a real read to confirm auth works."""
    db = firestore.client()
    db.collection('_health').document('ping').get()

def init_firebase():
    global _firebase_ok
    with _firebase_lock:
        if _firebase_ok is not None:
            return _firebase_ok
        try:
            if not firebase_admin._apps:
                service_account = json.loads(os.environ.get('FIREBASE_SERVICE_ACCOUNT', '{}'))
                cred = credentials.Certificate(service_account)
                initialize_app(cred)
            # Probe with 8-second timeout so Lambda never hangs 30s on bad credentials
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
                future = ex.submit(_test_firestore_connection)
                future.result(timeout=8)
            _firebase_ok = True
        except concurrent.futures.TimeoutError:
            print('[Samantha] Firebase probe timed out — running in offline mode')
            _firebase_ok = False
        except Exception as e:
            print(f'[Samantha] Firebase unavailable: {e}')
            _firebase_ok = False
    return _firebase_ok

# ─────────────────────────────────────────
# DATA FETCHERS
# ─────────────────────────────────────────
def get_user_profile(db, user_id):
    try:
        doc = db.document(f'users/{user_id}/profile/main').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}

def get_recent_conversations(db, user_id, limit=20):
    """Get last N conversation turns for in-context memory"""
    try:
        docs = db.collection(f'users/{user_id}/conversations') \
                 .order_by('timestamp', direction='DESCENDING') \
                 .limit(limit).stream()
        convs = [d.to_dict() for d in docs]
        convs.reverse()  # chronological order
        return convs
    except:
        return []

def get_important_memories(db, user_id, limit=10):
    """Get high-importance long-term memories"""
    try:
        docs = db.collection(f'users/{user_id}/memories') \
                 .order_by('importance', direction='DESCENDING') \
                 .limit(limit).stream()
        return [d.to_dict() for d in docs]
    except:
        return []

def resolve_date_from_message(user_message, reference_date=None):
    """
    Extract a target date from natural language.
    Returns (date_obj, label_str) or (None, None) if no date found.
    """
    import datetime as _dt
    import re
    today = reference_date or _dt.date.today()
    msg = user_message.lower().strip()

    # today / tomorrow
    if re.search(r'\btoday\b', msg):
        return today, 'today'
    if re.search(r'\btomorrow\b', msg):
        d = today + _dt.timedelta(days=1)
        return d, d.strftime('%A, %B %d')

    # "in X days"
    m = re.search(r'in (\d+) days?', msg)
    if m:
        d = today + _dt.timedelta(days=int(m.group(1)))
        return d, d.strftime('%A, %B %d')

    # "on the Nth" / "15th", "3rd", "22nd"
    m = re.search(r'(?:on the |for the |for )?(\d{1,2})(?:st|nd|rd|th)', msg)
    if m:
        day_num = int(m.group(1))
        for month_offset in [0, 1]:
            try:
                import calendar
                if month_offset == 0:
                    candidate = today.replace(day=day_num)
                else:
                    if today.month == 12:
                        candidate = _dt.date(today.year+1, 1, day_num)
                    else:
                        candidate = today.replace(month=today.month+1, day=day_num)
                if candidate >= today:
                    return candidate, candidate.strftime('%B %d')
            except ValueError:
                continue

    # Month name + day: "15th March", "March 15", "15 March"
    months = {
        'january':1,'february':2,'march':3,'april':4,'may':5,'june':6,
        'july':7,'august':8,'september':9,'october':10,'november':11,'december':12,
        'jan':1,'feb':2,'mar':3,'apr':4,'jun':6,'jul':7,'aug':8,
        'sep':9,'sept':9,'oct':10,'nov':11,'dec':12
    }
    for month_name, month_num in months.items():
        if month_name in msg:
            m2 = re.search(r'(\d{1,2})(?:st|nd|rd|th)?\s+' + month_name, msg)
            if not m2:
                m2 = re.search(month_name + r'\s+(\d{1,2})', msg)
            if m2:
                day_num = int(m2.group(1))
                year = today.year
                try:
                    candidate = _dt.date(year, month_num, day_num)
                    if candidate < today:
                        candidate = _dt.date(year+1, month_num, day_num)
                    return candidate, candidate.strftime('%B %d')
                except ValueError:
                    pass

    # Day names: "monday", "this friday", "next tuesday"
    day_names = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday']
    for i, day in enumerate(day_names):
        if day in msg:
            days_ahead = (i - today.weekday()) % 7
            if 'next' in msg:
                if days_ahead == 0:
                    days_ahead = 7
                else:
                    days_ahead += 7
            elif days_ahead == 0:
                return today, 'today'
            candidate = today + _dt.timedelta(days=days_ahead)
            return candidate, candidate.strftime('%A, %B %d')

    return None, None


def get_todays_plan(db, user_id):
    try:
        today = datetime.date.today().isoformat()
        doc = db.document(f'users/{user_id}/dailyPlans/{today}').get()
        if not doc.exists:
            return {}
        plan = doc.to_dict()
        # Safety check: if the plan has a 'date' field and it's not today, it's stale
        plan_date = plan.get('date', today)
        if plan_date != today:
            print(f"WARNING: Plan date {plan_date} != today {today} — returning empty to trigger fresh generation")
            return {}
        return plan
    except:
        return {}

def get_habit_streaks(db, user_id):
    """Get current habit streak data"""
    try:
        doc = db.document(f'users/{user_id}/habits/streaks').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}

def get_weekly_summary(db, user_id):
    """Get this week's mood and activity summary"""
    try:
        week_start = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
        docs = db.collection(f'users/{user_id}/dailyLogs') \
                 .where('date', '>=', week_start) \
                 .order_by('date', direction='DESCENDING') \
                 .limit(7).stream()
        return [d.to_dict() for d in docs]
    except:
        return []

# ─────────────────────────────────────────
# MOOD DETECTION
# ─────────────────────────────────────────
def detect_mood(message):
    """Simple keyword-based mood detection"""
    message_lower = message.lower()

    stressed = ['tired', 'exhausted', 'overwhelmed', 'stressed', 'anxious',
                'worried', 'cant sleep', "can't sleep", 'headache', 'burnout',
                'too much', 'behind', 'failing', 'struggling', 'difficult']

    happy = ['great', 'amazing', 'excited', 'happy', 'good', 'wonderful',
             'fantastic', 'achieved', 'done', 'completed', 'progress',
             'published', 'finished', 'success', 'proud']

    sad = ['sad', 'depressed', 'lonely', 'low', 'down', 'hopeless',
           'giving up', 'pointless', 'no motivation', 'unmotivated']

    focused = ['working on', 'focusing', 'planning', 'lets talk about',
               "let's talk", 'help me', 'what should', 'how do i']

    if any(w in message_lower for w in stressed):
        return 'stressed'
    elif any(w in message_lower for w in sad):
        return 'sad'
    elif any(w in message_lower for w in happy):
        return 'happy'
    elif any(w in message_lower for w in focused):
        return 'focused'
    return 'neutral'

# ─────────────────────────────────────────
# MEMORY SAVING
# ─────────────────────────────────────────
def save_conversation(db, user_id, user_msg, ai_reply, mood, session_id=None):
    """Save full conversation turn with session grouping"""
    import uuid
    try:
        db.collection(f'users/{user_id}/conversations').add({
            'userMessage': user_msg,
            'aiReply': ai_reply,
            'mood': mood,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'date': datetime.date.today().isoformat(),
            'session_id': session_id or str(uuid.uuid4())
        })
    except Exception as e:
        print(f"Conversation save error: {e}")


def log_interaction(db, user_id, user_msg, intent, agent_used, success, response_ms=0):
    """Phase D/E: Log every interaction for self-improvement analysis"""
    try:
        db.collection(f'users/{user_id}/interaction_logs').add({
            'message_preview': user_msg[:100],
            'intent': intent,
            'agent_used': agent_used or 'chat',
            'success': success,
            'response_ms': response_ms,
            'date': datetime.date.today().isoformat(),
            'timestamp': firestore.SERVER_TIMESTAMP,
        })
    except Exception as e:
        print(f"Interaction log error: {e}")

def extract_and_save_memory(db, user_id, user_msg, ai_reply, mood):
    """Use Groq to extract important facts worth remembering long-term"""
    try:
        extraction_prompt = f"""Extract important facts from this conversation worth remembering long-term.
User said: "{user_msg}"
Samantha replied: "{ai_reply}"

Return ONLY a JSON object like this (or null if nothing important):
{{
  "memory": "One sentence summary of the important fact",
  "category": "goal|habit|emotion|achievement|challenge|preference|relationship",
  "importance": 7
}}

Only extract truly meaningful information — goals achieved, challenges mentioned, important decisions, emotional events, or life updates. Skip small talk."""

        response = ask_groq([{'role': 'user', 'content': extraction_prompt}], max_tokens=200)
        clean = response.strip().replace('```json', '').replace('```', '').strip()

        if clean and clean != 'null' and '{' in clean:
            memory_data = json.loads(clean)
            if memory_data and memory_data.get('memory'):
                db.collection(f'users/{user_id}/memories').add({
                    'text': memory_data['memory'],
                    'category': memory_data.get('category', 'general'),
                    'importance': memory_data.get('importance', 5),
                    'mood_context': mood,
                    'timestamp': firestore.SERVER_TIMESTAMP,
                    'date': datetime.date.today().isoformat()
                })
    except Exception as e:
        print(f"Memory extraction error: {e}")

def update_daily_log(db, user_id, mood, user_msg):
    """Update today's mood and activity log"""
    try:
        today = datetime.date.today().isoformat()
        log_ref = db.document(f'users/{user_id}/dailyLogs/{today}')
        log_doc = log_ref.get()

        if log_doc.exists:
            existing = log_doc.to_dict()
            moods = existing.get('moods', [])
            moods.append(mood)
            log_ref.update({
                'moods': moods,
                'lastMessage': user_msg[:100],
                'updatedAt': firestore.SERVER_TIMESTAMP
            })
        else:
            log_ref.set({
                'date': today,
                'moods': [mood],
                'lastMessage': user_msg[:100],
                'createdAt': firestore.SERVER_TIMESTAMP,
                'updatedAt': firestore.SERVER_TIMESTAMP
            })
    except Exception as e:
        print(f"Daily log error: {e}")

# ─────────────────────────────────────────
# GROQ AI
# ─────────────────────────────────────────
def ask_groq(messages, max_tokens=1024):
    response = requests.post(GROQ_URL,
        headers={
            'Authorization': f'Bearer {GROQ_API_KEY}',
            'Content-Type': 'application/json'
        },
        json={
            'model': 'llama-3.3-70b-versatile',
            'max_tokens': max_tokens,
            'messages': messages,
            'temperature': 0.6
        },
        timeout=30
    )
    data = response.json()
    if 'choices' not in data:
        # Log the actual Groq error so we can see it in CloudWatch
        error_msg = data.get('error', {})
        if isinstance(error_msg, dict):
            error_msg = error_msg.get('message', str(data))
        print(f"Groq API error (HTTP {response.status_code}): {error_msg}")
        raise Exception(f"Groq API error: {error_msg}")
    return data['choices'][0]['message']['content']

# ═════════════════════════════════════════════════════════
# JARVIS LAYER — INTENT CLASSIFIER + AGENT ORCHESTRATOR
# ═════════════════════════════════════════════════════════

def classify_intent(user_message):
    """Classify user intent to route to the right agent"""
    prompt = f"""You are a precise intent classifier for a personal AI assistant. Classify this message into exactly ONE intent.

Message: "{user_message}"

━━━ INTENT CATEGORIES ━━━
- chat: ANY question about the existing plan, asking what to do at a time, asking about activities, greetings, small talk, status updates
- research: find info, news, analysis, what is X, tell me about X, movies, events, current news
- content: create script, write content, make a script, draft a post, content for Phokat ka Gyan, script for Corporate Kurukshetra, YouTube idea, Instagram caption, debate script, write a reel script
- code: build a widget, write a Lambda function, create a Flutter screen, generate code for X, write a function that does Y, code for feature Z
- plan: "make me a plan for today", "create today\'s schedule", "plan my day" — ONLY when explicitly asking to CREATE a new plan
- tomorrow_ask: reading/asking about tomorrow\'s plan — "what are plans for tomorrow", "brief me on tomorrow", "show tomorrow\'s schedule"
- tomorrow_modify: giving NEW SCHEDULE FACTS that change tomorrow\'s plan — "tomorrow is WFH", "I have a meeting at 3pm tomorrow", "cancel travel tomorrow", "tomorrow starts at 8am"
- date_modify: changing plan for a SPECIFIC date that is NOT today or tomorrow — "update my plan for Thursday", "reschedule Friday", "I have a holiday on 15th March", "next Monday is WFH"
- modify_plan: explicitly asking to CHANGE today\'s plan — "remove exercise from today", "add a task to today", "reschedule my afternoon", "cancel my evening plan"
- project: build app, start project, work on Traveler Tree / Gita App
- reflect: how am I doing, weekly review, my progress, show me my week
- monitor: quick check on habits/streaks, am I on track, performance report, how are my streaks
- habit: mark habit done, check streak, I finished X, I did my X today
- strategy: life strategy, monthly plan, goal conflicts, what to focus on this month, rebalance my life
- execute: set reminder, add goal, send notification

━━━ CRITICAL CLASSIFICATION RULES ━━━
THESE ARE "chat" NOT modify_plan:
- "what should I do after 5:30 PM" → chat (asking a question about schedule)
- "what to be done after 5:30 PM as per the schedule" → chat (reading existing plan)
- "what\'s left for today" → chat (status question)
- "what are my tasks now" → chat (asking about existing plan)
- "brief me on today" → chat (reading existing plan)
- "what is pending" → chat (status question)

THESE ARE modify_plan:
- "remove exercise from today\'s plan" → modify_plan
- "add a meeting at 3pm today" → modify_plan  
- "today I have a holiday, reschedule everything" → modify_plan

THESE ARE tomorrow_modify:
- "tomorrow is WFH from 8am to 5pm" → tomorrow_modify
- "I have a client meeting tomorrow at 2pm" → tomorrow_modify
- "tomorrow I need to go to office" → tomorrow_modify
- "but tomorrow I go to office" → tomorrow_modify
- "tomorrow is office day" → tomorrow_modify

THESE ARE date_modify (specific future date, not today/tomorrow):
- "update my plan for Thursday" → date_modify
- "next Monday is WFH" → date_modify
- "I have a holiday on 15th March" → date_modify
- "reschedule my Friday plan" → date_modify
- "add a meeting on 20th at 3pm" → date_modify
- "this Saturday I am travelling" → date_modify

THESE ARE modify_plan (TODAY only):
- "whenever I go to office I cannot do pencil sketch" → modify_plan (teaching a rule + updating today)
- "remove sketch from today" → modify_plan
- "plan in the plan tab is not updated, please update it" → modify_plan

THESE ARE content (script/post creation — not research, not plan):
- "create a script for Phokat ka Gyan" → content
- "write a reel script on water pollution" → content
- "script for Corporate Kurukshetra video" → content
- "give me YouTube video ideas" → content
- "Instagram caption for my travel post" → content
- "debate script for Sunday" → content
- "make a short video script on [any topic]" → content

THESE ARE code (generating actual code):
- "build me a Flutter widget for habit tracking" → code
- "write a Lambda function that sends daily reminders" → code
- "create a screen for research reports" → code
- "write code to parse Firestore data" → code
- "generate a Dart class for user profile" → code

CRITICAL DAY RULES:
- Any message with "tomorrow" + schedule fact → ALWAYS tomorrow_modify, NEVER modify_plan
- Any message with day name / date + schedule fact (not today/tomorrow) → date_modify
- Any message with "whenever I go to office" (global rule) → modify_plan for today only
- "plan is not updated" / "update the plan" without specifying tomorrow → modify_plan for TODAY
- NEVER change today\'s plan when intent is tomorrow_modify
- NEVER change tomorrow\'s plan when intent is modify_plan

Return ONLY valid JSON, no other text:
{{"intent": "chat", "confidence": 0.9, "sub_task": "brief description of what user wants"}}"""

    try:
        result = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=120)
        clean = result.strip().replace('```json','').replace('```','').strip()
        parsed = json.loads(clean)
        return parsed.get('intent', 'chat'), parsed.get('sub_task', '')
    except:
        return 'chat', ''


# ─────────────────────────────────────────
# CONSTRAINT EXTRACTOR — the intelligence layer
# Reads what user said and returns structured rules
# ─────────────────────────────────────────
def extract_schedule_constraints(user_message, target_date_str, base_day_name, is_weekend):
    """
    Given a user message like 'tomorrow is WFH, 8am to 5pm, no travel',
    use Groq to extract structured constraints that override the default schedule.
    Returns a dict with keys: work_mode, work_start, work_end, commute, meetings, notes, extra_time
    """
    prompt = f"""You are a schedule constraint extractor for a personal AI assistant.

The user said: "{user_message}"
Target day: {target_date_str} ({base_day_name})
Default assumption: {"no corporate job" if is_weekend else "corporate job, leave 7:10am, return 7:15pm"}

Extract EXACT schedule constraints the user mentioned. Return ONLY valid JSON:
{{
  "work_mode": "wfh" | "office" | "holiday" | "half_day" | "normal",
  "work_start": "8:00 AM" or null,
  "work_end": "5:00 PM" or null,
  "commute_cancelled": true or false,
  "meetings": [{{"time": "...", "description": "..."}}],
  "cancelled_tasks": ["task name if any"],
  "extra_free_time_morning": true or false,
  "extra_free_time_evening": true or false,
  "notes": "one line summary of what changed"
}}

Rules:
- "WFH" or "work from home" → work_mode: "wfh", commute_cancelled: true
- "starts at 8am" → work_start: "8:00 AM"
- "till 5pm" or "until 5" → work_end: "5:00 PM"
- "travel cancelled" → commute_cancelled: true
- If work starts later than usual OR WFH → extra_free_time_morning: true
- If work ends earlier than 7:15pm → extra_free_time_evening: true
- Only extract what is explicitly mentioned — do not assume"""

    try:
        result = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=300)
        clean = result.strip().replace('```json','').replace('```','').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}')+1]
        return json.loads(clean)
    except Exception as e:
        print(f"constraint extractor error: {e}")
        return {
            'work_mode': 'normal', 'work_start': None, 'work_end': None,
            'commute_cancelled': False, 'meetings': [], 'cancelled_tasks': [],
            'extra_free_time_morning': False, 'extra_free_time_evening': False,
            'notes': user_message[:100]
        }


def build_constraint_aware_plan(db, user_id, target_date, constraints, existing_plan_str=''):
    """
    Generate a plan that strictly respects extracted constraints.
    This is what makes Samantha actually intelligent about schedule changes.
    """
    day_name = target_date.strftime('%A, %B %d %Y')
    is_weekend = target_date.weekday() >= 5

    # Build a precise schedule description from constraints
    work_mode = constraints.get('work_mode', 'normal')
    work_start = constraints.get('work_start')
    work_end = constraints.get('work_end')
    commute_cancelled = constraints.get('commute_cancelled', False)
    meetings = constraints.get('meetings', [])
    cancelled = constraints.get('cancelled_tasks', [])
    extra_morning = constraints.get('extra_free_time_morning', False)
    extra_evening = constraints.get('extra_free_time_evening', False)

    # Build precise schedule description
    # Explicit office detection — user said "go to office" / "office day"
    if work_mode == 'normal':
        msg_check = str(constraints.get('_raw_message', '')).lower()
        if any(w in msg_check for w in ['office', 'go to work', 'commute', 'leave for work']):
            work_mode = 'office'
            constraints['work_mode'] = 'office'

    if work_mode == 'wfh':
        schedule_desc = f"WORK FROM HOME day. NO commute. NO travel. Work starts {work_start or '9:00 AM'}, ends {work_end or '6:00 PM'}."
        if extra_morning:
            schedule_desc += f" Morning is FREE before {work_start or '9:00 AM'} — use it for habits."
        if extra_evening:
            schedule_desc += f" Evening is FREE after {work_end or '6:00 PM'} — more time for creative work."
    elif work_mode == 'holiday':
        schedule_desc = "HOLIDAY / DAY OFF. Full day free. No corporate work."
    elif work_mode == 'half_day':
        schedule_desc = f"HALF DAY. Work {work_start or 'morning'} to {work_end or 'afternoon'} only."
    elif is_weekend:
        schedule_desc = f"Weekend — {day_name}. No corporate job. Full day available."
    else:
        leave_time = "7:10 AM" if not commute_cancelled else None
        return_time = "7:15 PM" if not commute_cancelled else None
        if work_start or work_end:
            schedule_desc = f"Corporate job day. Work {work_start or '9AM'} to {work_end or '6PM'}."
            if commute_cancelled:
                schedule_desc += " No commute today."
            else:
                schedule_desc += f" Leave {leave_time}, return {return_time}."
        else:
            schedule_desc = f"Normal corporate day. Leave 7:10 AM, return 7:15 PM."
        if target_date.strftime('%A') in ['Monday', 'Wednesday', 'Friday']:
            schedule_desc += " Corporate Kurukshetra video at 7:30 PM."
        # Permanent office constraint Sudeep taught Samantha
        schedule_desc += " RULE: Pencil sketch ONLY after 7:15 PM return from office. Never in morning or during work hours."

    meetings_str = ""
    if meetings:
        meetings_str = "FIXED MEETINGS (block these):\n" + "\n".join([f"- {m.get('time','')}: {m.get('description','')}" for m in meetings])

    cancelled_str = ""
    if cancelled:
        cancelled_str = f"DO NOT include these (user cancelled): {', '.join(cancelled)}"

    existing_str = f"Previous plan to revise:\n{existing_plan_str}" if existing_plan_str else "No previous plan."

    # Build explicit FORBIDDEN and REQUIRED slot lists so Groq has no ambiguity
    forbidden_tasks = []
    required_evening_tasks = []

    if work_mode == 'wfh' or commute_cancelled:
        forbidden_tasks += [
            "leave for work", "commute", "return from work", "get ready for commute",
            "travel to office", "bus", "metro", "leave home"
        ]

    if work_mode == 'wfh':
        work_end_time = work_end or "6:00 PM"
        required_evening_tasks = [
            f"After {work_end_time}: ukulele practice (30 min)",
            f"After {work_end_time}: work on Phokat ka Gyan content or project",
            f"After {work_end_time}: sketching if not done during day",
        ]
        # Monday has Corporate Kurukshetra video
        if target_date.strftime('%A') in ['Monday', 'Wednesday', 'Friday']:
            required_evening_tasks.append(f"7:30 PM: Corporate Kurukshetra video (30 min)")

    forbidden_str = ("FORBIDDEN — NEVER include these tasks:\n" +
                     "\n".join(f"- {t}" for t in forbidden_tasks)) if forbidden_tasks else ""

    required_evening_str = ("REQUIRED EVENING TASKS — must include these after work:\n" +
                            "\n".join(f"- {t}" for t in required_evening_tasks)) if required_evening_tasks else ""

    # Load learned rules from profile
    profile = get_user_profile(db, user_id)
    learned_rules = profile.get('learned_rules', [])
    learned_rules_str = ""
    if learned_rules:
        learned_rules_str = "━━━ RULES SUDEEP TAUGHT ME (always apply) ━━━\n" + "\n".join(f"- {r}" for r in learned_rules)

    prompt = f"""You are Sudeep's personal AI. Create a PRECISE daily plan for {day_name}.

━━━ SCHEDULE FACTS (non-negotiable) ━━━
{schedule_desc}

{forbidden_str}

{required_evening_str}

{meetings_str}
{cancelled_str}

{learned_rules_str}

━━━ DAILY HABITS (fit wherever possible) ━━━
- Exercise: 30 min — first slot of the morning
- Daily short (Phokat ka Gyan): 30 min — 8:30 AM if free slot exists, else earliest morning gap
- Ukulele: 30 min — if WFH or free morning, do before work; else evening after work
- Pencil sketch: 30-60 min — lunch break if available, else evening

━━━ RULES FOR WFH DAYS ━━━
- Morning slots (before work_start): exercise, ukulele, daily short, get ready
- Work block ({work_start or "8:00 AM"} to {work_end or "6:00 PM"}): show as "Work (WFH)" with lunch break at 1 PM
- Evening slots (after {work_end or "6:00 PM"}): MUST schedule ukulele, sketch, Phokat ka Gyan content, project work
- Do NOT leave evening as just "free time" — fill it with productive habits
- NO commute tasks. NO "return from work". NO "leave for office". Sudeep is HOME all day.

━━━ OUTPUT FORMAT ━━━
Return ONLY valid JSON — no extra text, no markdown:
{{
  "morning":   [{{"time": "H:MM AM", "task": "exact task", "duration": "X min", "domain": "domain"}}],
  "afternoon": [{{"time": "H:MM PM", "task": "exact task", "duration": "X min", "domain": "domain"}}],
  "evening":   [{{"time": "H:MM PM", "task": "exact task", "duration": "X min", "domain": "domain"}}],
  "top_priority": "single most important task",
  "motivation": "one energising sentence for Sudeep",
  "schedule_note": "one line summary of what is different today"
}}

Fill all three sections (morning/afternoon/evening) with real tasks. Evening must have at least 3 tasks."""

    try:
        plan_json = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=900)
        clean = plan_json.strip().replace('```json','').replace('```','').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}')+1]
        plan = json.loads(clean)
        plan.setdefault('completed_tasks', [])
        plan['date'] = target_date.isoformat()
        plan['constraints_applied'] = constraints
        return plan
    except Exception as e:
        print(f"build_constraint_aware_plan error: {e}")
        return None


# ─────────────────────────────────────────
# RESEARCH AGENT — multi-step deep research
# ─────────────────────────────────────────
def research_agent(db, user_id, query):
    """Multi-step research: generate queries → search → synthesize → save report"""
    try:
        # Step 1: Generate 3 targeted search queries
        query_prompt = f"""Generate 3 specific search queries to thoroughly research: "{query}"
Return ONLY JSON array: ["query1", "query2", "query3"]"""
        queries_raw = ask_groq([{'role': 'user', 'content': query_prompt}], max_tokens=150)
        queries_clean = queries_raw.strip().replace('```json','').replace('```','').strip()
        try:
            queries = json.loads(queries_clean)
        except:
            queries = [query]

        # Step 2: Search all queries
        all_results = []
        for q in queries[:3]:
            result = web_search(q, num_results=3)
            if result:
                all_results.append(f"[Query: {q}]\n" + str(result))

        if not all_results:
            return None

        combined = '\n\n'.join(all_results)

        # Step 3: Synthesize into structured report
        synthesis_prompt = f"""Based on these search results, write a clear concise research summary for Sudeep about: "{query}"

Search results:
{combined}

Write in 3-4 paragraphs. Be factual, practical, and relevant to Sudeep's context (content creator, app developer, Indian audience).
End with 2-3 actionable insights or recommendations."""

        report = ask_groq([{'role': 'user', 'content': synthesis_prompt}], max_tokens=600)

        # Step 4: Save to Firestore
        try:
            db.collection(f'users/{user_id}/research_reports').add({
                'query': query,
                'report': report,
                'queries_used': queries,
                'timestamp': firestore.SERVER_TIMESTAMP,
                'date': datetime.date.today().isoformat(),
                'status': 'completed'
            })
        except Exception as e:
            print(f'Research save error: {e}')

        return report

    except Exception as e:
        print(f'Research agent error: {e}')
        return None


# ─────────────────────────────────────────
# PLANNER AGENT — goal decomposition
# ─────────────────────────────────────────
def planner_agent(db, user_id, goal, profile):
    """Break a goal into 30-day actionable project plan"""
    try:
        prompt = f"""Create a practical 30-day project plan for Sudeep.
Goal: {goal}
His constraints: corporate job Mon-Fri 9am-7pm, limited to evenings (8-10pm) and weekends.

Return ONLY valid JSON:
{{
  "project_title": "...",
  "goal": "{goal}",
  "success_metric": "How we know it's done",
  "week_1_focus": "...",
  "week_2_focus": "...",
  "week_3_focus": "...",
  "week_4_focus": "...",
  "daily_time_needed": "X minutes",
  "best_time_slot": "e.g. 8:30pm weekdays",
  "milestones": [
    {{"day": 7, "milestone": "...", "deliverable": "..."}},
    {{"day": 14, "milestone": "...", "deliverable": "..."}},
    {{"day": 21, "milestone": "...", "deliverable": "..."}},
    {{"day": 30, "milestone": "...", "deliverable": "..."}}
  ],
  "daily_tasks": [
    {{"week": 1, "task": "...", "duration_min": 30, "domain": "..."}}
  ],
  "blockers": ["potential challenge 1", "potential challenge 2"],
  "motivation": "Personal message for Sudeep about why this matters"
}}"""

        plan_raw = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=800)
        clean = plan_raw.strip().replace('```json','').replace('```','').strip()
        plan = json.loads(clean)

        # Save project to Firestore
        project_ref = db.collection(f'users/{user_id}/projects').add({
            'title': plan.get('project_title', goal),
            'goal': goal,
            'plan': plan,
            'status': 'active',
            'created': firestore.SERVER_TIMESTAMP,
            'date': datetime.date.today().isoformat(),
            'progress_percent': 0,
            'domain': 'general'
        })

        return plan

    except Exception as e:
        print(f'Planner agent error: {e}')
        return None


# ─────────────────────────────────────────
# STRATEGY AGENT — monthly life strategy & goal conflict detection
# ─────────────────────────────────────────
def strategy_agent(db, user_id, query, profile):
    """Generate monthly life strategy with goal conflict detection and rebalancing suggestions"""
    try:
        projects = get_active_projects(db, user_id)
        streaks = get_habit_streaks(db, user_id)
        logs = get_weekly_summary(db, user_id)
        project_summary = json.dumps([
            {'title': p.get('title', ''), 'goal': p.get('goal', ''), 'status': p.get('status', '')}
            for p in projects[:5]
        ])
        habit_summary = json.dumps(streaks, default=str)
        mood_counts = {}
        for log in logs:
            mood = log.get('mood', 'neutral')
            mood_counts[mood] = mood_counts.get(mood, 0) + 1
        goals = profile.get('goals', [])
        projects_info = profile.get('projects', {})
        prompt = f"""You are Samantha, Sudeep's personal AI Chief of Staff. Generate a monthly life strategy analysis.
USER QUERY: "{query}"
CURRENT PROJECTS: {project_summary if projects else "No active projects yet"}
HABIT STREAKS: {habit_summary}
MOOD PATTERN: {json.dumps(mood_counts)}
LIFE CONTEXT: Goals: {json.dumps(goals)}, Projects: {json.dumps(projects_info)}
Return ONLY valid JSON:
{{"strategy_summary": "2-3 sentence overview","domain_scores": {{"health": {{"score": 0,"trend": "stable","note": ""}},"creativity": {{"score": 0,"trend": "stable","note": ""}},"career": {{"score": 0,"trend": "stable","note": ""}},"learning": {{"score": 0,"trend": "stable","note": ""}},"finance": {{"score": 0,"trend": "stable","note": ""}}}},"goal_conflicts": [{{"conflict": "example","severity": "medium","suggestion": "how to resolve"}}],"top_recommendation": "single most important change","schedule_rebalance": {{"drop_or_reduce": [],"increase": [],"add_new": []}},"this_month_focus": "one sentence","samanthas_message": "personal message"}}"""
        strategy_raw = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=900)
        clean = strategy_raw.strip().replace('```json', '').replace('```', '').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}')+1]
        strategy = json.loads(clean)
        try:
            db.collection(f'users/{user_id}/strategy_reports').add({
                **strategy, 'query': query,
                'generated_at': firestore.SERVER_TIMESTAMP,
                'date': datetime.date.today().isoformat(),
                'month': datetime.date.today().strftime('%Y-%m'),
            })
        except Exception as e:
            print(f'Strategy save error: {e}')
        return strategy
    except Exception as e:
        print(f'Strategy agent error: {e}')
        return None


# ─────────────────────────────────────────
# MONITORING AGENT — habit pattern analysis & productivity trends
# ─────────────────────────────────────────
def monitoring_agent(db, user_id, query):
    """Analyze habit patterns, productivity trends, mood correlations over 14 days"""
    try:
        two_weeks_ago = (datetime.date.today() - datetime.timedelta(days=14)).isoformat()
        logs = list(db.collection(f'users/{user_id}/daily_logs').where('date', '>=', two_weeks_ago).limit(30).stream())
        log_data = [l.to_dict() for l in logs]
        streaks = get_habit_streaks(db, user_id)
        convs = list(db.collection(f'users/{user_id}/conversations').where('date', '>=', two_weeks_ago).limit(30).stream())
        conv_moods = [c.to_dict().get('mood', 'neutral') for c in convs]
        mood_dist = {}
        for m in conv_moods:
            mood_dist[m] = mood_dist.get(m, 0) + 1
        habit_days = {}
        for log in log_data:
            for h in log.get('habits_completed', []):
                habit_days[h] = habit_days.get(h, 0) + 1
        prompt = f"""Analyze Sudeep's productivity and habit patterns over the last 14 days.
USER QUESTION: "{query}"
HABIT STREAKS: {json.dumps(streaks, default=str)}
HABIT COMPLETION (days/14): {json.dumps(habit_days)}
MOOD DISTRIBUTION: {json.dumps(mood_dist)}
TOTAL CONVERSATIONS: {len(conv_moods)}
Return ONLY valid JSON:
{{"performance_score": 0,"summary": "2-3 sentence assessment","habit_analysis": [{{"habit": "exercise","completion_rate": "0/14","trend": "stable","insight": ""}}],"best_performing_area": "","needs_attention": "","mood_pattern": "","productivity_insight": "","streak_at_risk": "","action_for_tomorrow": "","samanthas_message": ""}}"""
        analysis_raw = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=700)
        clean = analysis_raw.strip().replace('```json', '').replace('```', '').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}')+1]
        analysis = json.loads(clean)
        try:
            db.collection(f'users/{user_id}/monitoring_reports').add({
                **analysis, 'query': query,
                'generated_at': firestore.SERVER_TIMESTAMP,
                'date': datetime.date.today().isoformat(),
            })
        except Exception as e:
            print(f'Monitoring save error: {e}')
        return analysis
    except Exception as e:
        print(f'Monitoring agent error: {e}')
        return None


# ─────────────────────────────────────────
# WEEKLY REFLECTION ENGINE
# ─────────────────────────────────────────
def generate_weekly_reflection(db, user_id):
    """Analyze last 7 days and generate personal insights"""
    try:
        # Get last 7 days conversations
        week_ago = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
        convs = list(
            db.collection(f'users/{user_id}/conversations')
            .where('date', '>=', week_ago)
            .limit(50).stream()
        )
        conv_data = [c.to_dict() for c in convs]

        # Get habit streaks
        streaks = get_habit_streaks(db, user_id)

        # Get daily logs
        logs = get_weekly_summary(db, user_id)

        # Build summary for analysis
        conv_summary = '\n'.join([
            f"- {c.get('date','')}: {c.get('userMessage','')[:80]}"
            for c in conv_data[-20:]
        ])

        habit_summary = json.dumps(streaks, default=str)

        mood_counts = {}
        for log in logs:
            mood = log.get('mood', 'neutral')
            mood_counts[mood] = mood_counts.get(mood, 0) + 1

        prompt = f"""Analyze Sudeep's week and generate a personal reflection.

CONVERSATIONS THIS WEEK:
{conv_summary if conv_summary else "No conversations recorded"}

HABIT STREAKS:
{habit_summary}

MOOD DISTRIBUTION:
{json.dumps(mood_counts)}

Generate a thoughtful weekly reflection. Return ONLY valid JSON:
{{
  "week_summary": "2-3 sentence summary of how the week went",
  "wins": ["win 1", "win 2", "win 3"],
  "missed_opportunities": ["what could have been better"],
  "habit_completion_rate": "X/4 habits consistently",
  "dominant_mood": "overall emotional tone",
  "top_domain": "which life area got most attention",
  "insights": ["deep personal observation 1", "deep personal observation 2"],
  "next_week_focus": "single most important thing for next week",
  "samanthas_message": "Warm personal message from Samantha to Sudeep about his week"
}}"""

        reflection_raw = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=700)
        clean = reflection_raw.strip().replace('```json','').replace('```','').strip()
        reflection = json.loads(clean)

        # Save to Firestore
        db.collection(f'users/{user_id}/weekly_reflections').add({
            **reflection,
            'week_of': datetime.date.today().isoformat(),
            'timestamp': firestore.SERVER_TIMESTAMP,
        })

        return reflection

    except Exception as e:
        print(f'Weekly reflection error: {e}')
        return None


# ─────────────────────────────────────────
# PROJECT / TASK MANAGEMENT
# ─────────────────────────────────────────
def get_active_projects(db, user_id):
    try:
        docs = db.collection(f'users/{user_id}/projects') \
                 .where('status', '==', 'active') \
                 .limit(10).stream()
        return [d.to_dict() for d in docs]
    except:
        return []

def save_task(db, user_id, task_title, domain, due_date=None, project_id=None):
    try:
        db.collection(f'users/{user_id}/tasks').add({
            'title': task_title,
            'domain': domain,
            'status': 'pending',
            'due_date': due_date or datetime.date.today().isoformat(),
            'project_id': project_id,
            'created': firestore.SERVER_TIMESTAMP,
        })
    except Exception as e:
        print(f'Task save error: {e}')

def log_agent_action(db, user_id, agent, action, result_summary):
    try:
        db.collection(f'users/{user_id}/agent_logs').add({
            'agent': agent,
            'action': action,
            'result_summary': result_summary[:200] if result_summary else '',
            'status': 'completed',
            'timestamp': firestore.SERVER_TIMESTAMP,
            'date': datetime.date.today().isoformat()
        })
    except Exception as e:
        print(f'Agent log error: {e}')


# ─────────────────────────────────────────
# AGENT ORCHESTRATOR — routes to right agent
# ─────────────────────────────────────────
def agent_orchestrator(db, user_id, user_message, intent, sub_task, profile):
    """Route to specialized agent based on intent, return (reply, agent_used, extra_data)"""

    if intent == 'research':
        report = research_agent(db, user_id, user_message)
        if report:
            log_agent_action(db, user_id, 'research_agent', user_message, report[:100])
            return report, 'research_agent', {}
        return None, None, {}

    elif intent == 'project':
        plan = planner_agent(db, user_id, user_message, profile)
        if plan:
            log_agent_action(db, user_id, 'planner_agent', user_message, plan.get('project_title',''))
            reply = f"Project plan created: **{plan.get('project_title', user_message)}**\n\n"
            reply += f"📅 Week 1: {plan.get('week_1_focus', '')}\n"
            reply += f"📅 Week 2: {plan.get('week_2_focus', '')}\n"
            reply += f"📅 Week 3: {plan.get('week_3_focus', '')}\n"
            reply += f"📅 Week 4: {plan.get('week_4_focus', '')}\n\n"
            reply += f"⏰ {plan.get('daily_time_needed', '30 min')} daily at {plan.get('best_time_slot', 'evening')}\n\n"
            reply += plan.get('motivation', '')
            return reply, 'planner_agent', {'project': plan}
        return None, None, {}

    elif intent == 'reflect':
        reflection = generate_weekly_reflection(db, user_id)
        if reflection:
            log_agent_action(db, user_id, 'reflection_agent', 'weekly_reflection', reflection.get('week_summary',''))
            reply = reflection.get('samanthas_message', '')
            if reflection.get('wins'):
                reply += '\n\n🏆 Wins this week: ' + ', '.join(reflection['wins'][:3])
            if reflection.get('next_week_focus'):
                reply += f"\n\n🎯 Next week: {reflection['next_week_focus']}"
            return reply, 'reflection_agent', {'reflection': reflection}
        return None, None, {}

    elif intent == 'plan':
        # Generate a fresh daily plan for TODAY
        try:
            new_plan = generate_daily_plan(db, user_id)
            log_agent_action(db, user_id, 'planner_agent', 'daily_plan_requested', 'plan generated')
            slot_summary = []
            for slot in (new_plan.get('morning', []) + new_plan.get('afternoon', []) + new_plan.get('evening', [])):
                t = slot.get('time', '')
                task = slot.get('task', '')
                if t and task:
                    slot_summary.append(f"{t} — {task}")
            lines = '\n'.join(slot_summary[:8])
            reply = f"Here's your plan for today:\n\n{lines}\n\n🎯 Top priority: {new_plan.get('top_priority', '')}\n\nPlan screen is updated — go check it!"
            return reply, 'planner_agent', {'plan': new_plan, 'plan_updated': True}
        except Exception as e:
            print(f'Plan intent error: {e}')
            return None, None, {}

    elif intent == 'tomorrow_ask':
        # READ existing tomorrow plan from Firestore — do NOT regenerate
        try:
            import datetime as _dt2
            tomorrow = _dt2.date.today() + _dt2.timedelta(days=1)
            day_name = tomorrow.strftime('%A, %B %d')
            plan_ref = db.document(f'users/{user_id}/dailyPlans/{tomorrow.isoformat()}')
            plan_doc = plan_ref.get()
            if plan_doc.exists:
                plan = plan_doc.to_dict()
                slot_summary = []
                for slot in (plan.get('morning', []) + plan.get('afternoon', []) + plan.get('evening', [])):
                    t = slot.get('time', '')
                    task = slot.get('task', '')
                    if t and task:
                        slot_summary.append(f"{t} — {task}")
                lines = '\n'.join(slot_summary[:10])
                reply = f"Here's your plan for tomorrow ({day_name}):\n\n{lines}\n\n🎯 Top priority: {plan.get('top_priority', '')}\n\nLet me know if you want to change anything — just tell me what\'s different."
                return reply, 'planner_agent', {'plan': plan, 'plan_date': tomorrow.isoformat()}
            else:
                # No plan saved yet — generate from fixed schedule rules ONLY (no chat context)
                base_day = tomorrow.strftime('%A')
                is_wknd = tomorrow.weekday() >= 5
                day_type = "weekend" if is_wknd else "office day (leaves 7:10 AM, returns 7:15 PM)"
                new_plan = generate_plan_for_date(db, user_id, tomorrow)
                slot_summary = []
                for slot in (new_plan.get('morning', []) + new_plan.get('afternoon', []) + new_plan.get('evening', [])):
                    t = slot.get('time', '')
                    task = slot.get('task', '')
                    if t and task:
                        slot_summary.append(f"{t} — {task}")
                lines = '\n'.join(slot_summary[:10])
                reply = f"No plan saved for tomorrow yet — created a default {base_day} plan ({day_type}):\n\n{lines}\n\n🎯 Top priority: {new_plan.get('top_priority', '')}\n\nIf tomorrow is different (WFH, holiday, late start), just tell me and I\'ll update only tomorrow."
                return reply, 'planner_agent', {'plan': new_plan, 'plan_date': tomorrow.isoformat(), 'plan_updated': True}
        except Exception as e:
            print(f'Tomorrow ask error: {e}')
            return None, None, {}

    elif intent == 'tomorrow_modify':
        # User is giving NEW CONTEXT to change tomorrow's plan — USE INTELLIGENCE
        try:
            import datetime as _dt2
            tomorrow = _dt2.date.today() + _dt2.timedelta(days=1)
            day_name = tomorrow.strftime('%A, %B %d')
            base_day_name = tomorrow.strftime('%A')
            is_weekend = tomorrow.weekday() >= 5

            # STEP 1: Extract structured constraints from what user said
            constraints = extract_schedule_constraints(
                user_message, day_name, base_day_name, is_weekend
            )
            constraints['_raw_message'] = user_message  # for office/WFH detection
            print(f"Extracted constraints: {constraints}")

            # STEP 2: Load existing plan if any, to show what's changing
            plan_ref = db.document(f'users/{user_id}/dailyPlans/{tomorrow.isoformat()}')
            plan_doc = plan_ref.get()
            existing_plan_str = ''
            if plan_doc.exists:
                existing = plan_doc.to_dict()
                slots = []
                for slot in (existing.get('morning', []) + existing.get('afternoon', []) + existing.get('evening', [])):
                    t = slot.get('time', ''); task = slot.get('task', '')
                    if t and task:
                        slots.append(f"{t} — {task}")
                existing_plan_str = '\n'.join(slots)

            # STEP 3: Build constraint-aware plan using the intelligence layer
            new_plan = build_constraint_aware_plan(db, user_id, tomorrow, constraints, existing_plan_str)

            if new_plan is None:
                return None, None, {}

            # STEP 4: Save to Firestore
            plan_ref.set({
                **new_plan,
                'generated_at': firestore.SERVER_TIMESTAMP,
                'date': tomorrow.isoformat(),
                'day': base_day_name,
                'modified_by_user': True,
                'modification_context': user_message,
                'constraints_applied': constraints,
            })
            log_agent_action(db, user_id, 'planner_agent', 'tomorrow_plan_modified',
                           new_plan.get('schedule_note', 'plan updated with user context'))

            # STEP 5: Build reply that confirms what changed
            slot_summary = []
            for slot in (new_plan.get('morning', []) + new_plan.get('afternoon', []) + new_plan.get('evening', [])):
                t = slot.get('time', ''); task = slot.get('task', '')
                if t and task:
                    slot_summary.append(f"{t} — {task}")
            lines = '\n'.join(slot_summary[:10])
            schedule_note = new_plan.get('schedule_note', constraints.get('notes', ''))
            work_mode = constraints.get('work_mode', 'normal')
            mode_emoji = '🏠' if work_mode == 'wfh' else '🏖️' if work_mode == 'holiday' else '📅'

            reply = f"Got it — updated tomorrow ({day_name}) for {mode_emoji} {work_mode.upper() if work_mode != 'normal' else 'your changes'}.\n\n"
            if schedule_note:
                reply += f"📝 {schedule_note}\n\n"
            reply += f"{lines}\n\n🎯 Top priority: {new_plan.get('top_priority', '')}\n\nPlan tab is updated. Tell me if anything else changes."
            return reply, 'planner_agent', {'plan': new_plan, 'plan_date': tomorrow.isoformat(), 'plan_updated': True}
        except Exception as e:
            print(f'Tomorrow modify error: {e}')
            import traceback; traceback.print_exc()
            return None, None, {}

    elif intent == 'modify_plan':
        # Modify TODAY's plan with intelligence — same constraint extractor
        try:
            import datetime as _dt2
            today = _dt2.date.today()
            day_name = today.strftime('%A, %B %d')
            base_day_name = today.strftime('%A')
            is_weekend = today.weekday() >= 5

            # Extract constraints from what user said
            constraints = extract_schedule_constraints(
                user_message, day_name, base_day_name, is_weekend
            )
            constraints['_raw_message'] = user_message  # for office/WFH detection

            plan_ref = db.document(f'users/{user_id}/dailyPlans/{today.isoformat()}')
            plan_doc = plan_ref.get()
            existing_plan_str = ''
            if plan_doc.exists:
                existing = plan_doc.to_dict()
                slots = []
                for slot in (existing.get('morning', []) + existing.get('afternoon', []) + existing.get('evening', [])):
                    t = slot.get('time', ''); task = slot.get('task', '')
                    if t and task:
                        slots.append(f"{t} — {task}")
                existing_plan_str = '\n'.join(slots)

            new_plan = build_constraint_aware_plan(db, user_id, today, constraints, existing_plan_str)
            if new_plan is None:
                return None, None, {}

            plan_ref.set({
                **new_plan,
                'generated_at': firestore.SERVER_TIMESTAMP,
                'date': today.isoformat(),
                'day': base_day_name,
                'modified_by_user': True,
                'modification_context': user_message,
                'constraints_applied': constraints,
            })
            log_agent_action(db, user_id, 'planner_agent', 'today_plan_modified',
                           new_plan.get('schedule_note', 'today plan updated'))

            # ── Detect permanent rule teaching ("whenever", "always", "every time") ──
            # Save to profile so all future plans respect it automatically
            msg_lower_rule = user_message.lower()
            learned_rule = None
            if any(w in msg_lower_rule for w in ['whenever', 'always', 'every time', 'never', 'every office day']):
                if 'sketch' in msg_lower_rule and ('office' in msg_lower_rule or 'work' in msg_lower_rule):
                    learned_rule = 'sketch_office_rule: pencil sketch only after 7:15 PM return on office days'
                elif 'ukulele' in msg_lower_rule and 'office' in msg_lower_rule:
                    learned_rule = 'ukulele_office_rule: ukulele only evening on office days'
            if learned_rule:
                try:
                    profile_ref = db.document(f'users/{user_id}/profile/main')
                    profile_ref.set({'learned_rules': firestore.ArrayUnion([learned_rule])}, merge=True)
                    print(f"Learned rule saved: {learned_rule}")
                except Exception as rule_err:
                    print(f"Rule save error: {rule_err}")

            slot_summary = []
            for slot in (new_plan.get('morning', []) + new_plan.get('afternoon', []) + new_plan.get('evening', [])):
                t = slot.get('time', ''); task = slot.get('task', '')
                if t and task:
                    slot_summary.append(f"{t} — {task}")
            lines = '\n'.join(slot_summary[:10])
            schedule_note = new_plan.get('schedule_note', constraints.get('notes', ''))
            rule_note = "\n\n✅ Got it — I've learned this rule for all future office day plans." if learned_rule else ""
            reply = f"Updated today's plan based on what you told me.\n\n"
            if schedule_note:
                reply += f"📝 {schedule_note}\n\n"
            reply += f"{lines}\n\n🎯 Top priority: {new_plan.get('top_priority', '')}\n\nPlan tab is updated.{rule_note}"
            return reply, 'planner_agent', {'plan': new_plan, 'plan_updated': True}
        except Exception as e:
            print(f'Modify plan error: {e}')
            return None, None, {}



    elif intent == 'content':
        # ── Content Creation Agent ──
        # Handles: Phokat ka Gyan scripts, Corporate Kurukshetra, YouTube, Instagram, Debate
        try:
            msg_lower = user_message.lower()
            profile = get_user_profile(db, user_id)

            # Detect content type
            if any(w in msg_lower for w in ['corporate kurukshetra', 'kurukshetra', 'corporate video', 'corporate script']):
                content_type = 'corporate_kurukshetra'
            elif any(w in msg_lower for w in ['youtube', 'long form', 'long-form', 'yt video', 'full video']):
                content_type = 'youtube'
            elif any(w in msg_lower for w in ['instagram', 'insta', 'caption', 'ig post']):
                content_type = 'instagram'
            elif any(w in msg_lower for w in ['debate', 'sunday debate', 'debate script']):
                content_type = 'debate'
            else:
                content_type = 'phokat_short'  # default — daily awareness short

            # Extract topic from message
            topic_prompt = f"""Extract the specific topic from this message. Return ONLY the topic as a short phrase (3-8 words max).
If no specific topic is mentioned, return "auto" (meaning Samantha should pick a relevant topic).
Message: "{user_message}"
Return ONLY the topic phrase or "auto"."""
            topic = ask_groq([{'role': 'user', 'content': topic_prompt}], max_tokens=50).strip().strip('"').strip("'")

            # Get recent scripts for style continuity
            try:
                recent_scripts = db.collection(f'users/{user_id}/content_scripts') \
                    .order_by('created_at', direction='DESCENDING').limit(3).stream()
                recent_titles = [s.to_dict().get('title','') for s in recent_scripts]
                style_context = f"Recent topics covered: {', '.join(recent_titles)}" if recent_titles else ""
            except:
                style_context = ""

            # Build content type specific prompt
            if content_type == 'phokat_short':
                # ── DAILY AWARENESS SCRIPT ENGINE (Full System) ──
                today_date = datetime.date.today().strftime('%B %d, %Y')
                today_weekday = datetime.date.today().strftime('%A')

                # Search for today's awareness date/event for accuracy
                awareness_context = ""
                if SERPER_API_KEY:
                    try:
                        search_q = f"awareness day {datetime.date.today().strftime('%B %d')} India 2025 national international"
                        search_results = search_web(search_q)
                        if search_results:
                            snippets = [r.get('snippet', '') for r in search_results[:3]]
                            awareness_context = f"\nWEB SEARCH RESULTS for today's awareness days:\n" + "\n".join(f"- {s}" for s in snippets if s)
                    except:
                        awareness_context = ""

                if topic == 'auto':
                    topic_instruction = f"""Today is {today_date} ({today_weekday}).
{awareness_context}
Pick the MOST socially relevant awareness day or topic for today's India.
✔ Real reason the date exists
✔ Most socially relevant, not most tragic
❌ No invention — facts only"""
                else:
                    topic_instruction = f"Topic: {topic}\nDate context: {today_date}"

                pkg_engine_prompt = f"""You are writing a script for "Phokat Ka Gyan" — Sudeep's daily awareness channel.

━━━ YOUR ROLE ━━━
You are NOT a teacher, preacher or newsreader.
You ARE a sharp observer in a chai-pe-charcha tone — someone who notices what feels "normal" but isn't, someone who explains power, incentives, fear, delay.
Tone: "Yeh cheez kabhi ajeeb nahi lagi tumhe?"

━━━ CONTENT PURPOSE ━━━
Create awareness videos that:
• Interrupt scrolling through curiosity, not commands
• Expose systems, not emotions
• Feel like insider truth, not homework
• Leave viewer slightly uncomfortable — but smarter
Journey: Confusion → Realisation → "Oh… that's how it works" → Mental upgrade

━━━ TOPIC ━━━
{topic_instruction}
{style_context}

━━━ HOOK RULES (CRITICAL) ━━━
BANNED FOREVER: "Stop scrolling" / "Humanity failed" / direct moral judgement
Hook MUST: sound conversational, create doubt or contradiction, withhold conclusion, feel incomplete without watching.
Hook MUST challenge or reverse a commonly held belief about the topic.
NOT just: "Yeh normal lagta hai" — but: "Jo cheez tum is baare mein sahi samajhte ho — wahi galat hai"

APPROVED HOOK PATTERNS (pick one, rotate):
A — Quiet Contradiction: "Yeh day celebrate hota hai… par reason almost kisi ko yaad nahi."
B — Incomplete Truth: "Hume lagta hai yeh problem logon ki wajah se hai. Par sach thoda aur uncomfortable hai."
C — Personal Doubt: "Mujhe pehle lagta tha yeh bilkul normal hai. Phir ek cheez samajh aayi."
D — System Gap: "Yeh issue isliye survive karta hai kyunki system ko isse fayda milta hai."
E — Normalised Absurdity: "Yeh cheez hume normal lagti hai. Honi nahi chahiye."

━━━ SCRIPT STRUCTURE (60-75 seconds) ━━━

1️⃣ HOOK (0–3s): One pattern above. End mid-thought.

2️⃣ CONTEXT SNAPSHOT (3–10s): One concrete situation. One group. Zero emotion.
Example tone: "Office meetings mein… schools mein… public systems mein…"

3️⃣ WHY THIS DATE EXISTS (10–20s): One trigger. One authority. One reason.
Tone: Neutral. Almost boring. (contrast boosts credibility)

4️⃣ THE MECHANISM (20–35s) — CORE:
• Explain ONE system only
• Use cause → effect
• Talk incentives, fear, delay, reward
• Hindi for pressure ("darr", "izzat", "adjust kar lo") / English for systems ("policy", "budget", "evaluation")
• Every abstract system must be paired with one concrete proxy (form/rule/meeting/budget line/silence/delay)
❌ No "society failed" / No emotional blame

5️⃣ PRESENT-DAY CONSEQUENCE (35–45s): One present-day example. Calm delivery. No outrage.
Tone: "Same system. Naye words."

6️⃣ PROOF OF POSSIBILITY (45–55s): One real example. One line. No celebration.
Purpose: Break helplessness, not sell hope.

7️⃣ VIEWER PIVOT (55–65s): Create mild cognitive discomfort — without telling viewer what to do.
✔ One mental shift OR explicitly say: "Iska individual solution nahi hai."
Approved: "Agar yeh abhi bhi normal lagta hai…" / "Yahan hum sochna band kar dete hain…"
Test: if the pivot feels "agreeable" → it's weak.

8️⃣ OPEN-ENDED CLOSE (65–70s): Leave tension unresolved.
"Isliye yeh day abhi bhi relevant hai." / "Most log yahan sochna band kar dete hain."
❌ No CTA / No "share/comment"

━━━ EMOTIONAL SPIKE RULE ━━━
One sharp spike (anger/irony/discomfort/blunt truth) AFTER the Mechanism section.
• One line only • Not a slogan • Does not accuse the viewer
Purpose: memorability without moral lecturing.

━━━ LANGUAGE RULES ━━━
✔ Hinglish ONLY — spoken, raw, uneven, short lines + pauses
❌ Formal English / Shuddh Hindi / Philosophy / Poetic writing
Rule: Agar yeh line tum kisi dost ko bol nahi sakte — cut it.

━━━ REQUIRED OUTPUT FORMAT ━━━

**1️⃣ TELEPROMPTER SCRIPT (60-75 sec)**
[Full script with section markers and timing]

**2️⃣ REEL COVER TEXT OPTIONS (3-5 options, Hinglish)**
[Short punchy text for reel thumbnail/first frame]

**3️⃣ INSTAGRAM CAPTION**
[Under 200 chars, no hashtags, conversational]

**4️⃣ YOUTUBE SHORTS CAPTION**
[Under 100 chars, SEO-aware]

━━━ SELF-AUDIT (run before outputting — if ANY is NO, rewrite) ━━━
☐ First 3 seconds feel natural, not scripted?
☐ Language feels desi, not translated?
☐ Mechanism is crystal clear with a concrete proxy?
☐ One moment made the viewer pause mentally?
☐ Viewer feels respected, not lectured?
☐ This sounds like Phokat Ka Gyan, not a seminar?
☐ Hook challenges or reverses an assumption?
☐ Viewer pivot creates mild discomfort, not agreement?

━━━ FINAL QUALITY GATE ━━━
Publish only if it:
✔ Triggers discussion, not just agreement
✔ Changes how the viewer thinks
✔ Is worth defending in comments
Depth > frequency. Clarity > emotion. Insight > outrage."""

                prompt = pkg_engine_prompt

            elif content_type == 'corporate_kurukshetra':
                if topic == 'auto':
                    topic_instruction = "Pick a relatable corporate life topic — office politics, work-life balance, promotions, managers, deadlines, corporate culture in India."
                else:
                    topic_instruction = f"Topic: {topic}"

                prompt = f"""You are writing a script for Sudeep\'s "Corporate Kurukshetra" series — commentary on corporate life in India.

CHANNEL STYLE:
- Hindi/Hinglish, witty and relatable
- Insider perspective — Sudeep works in a corporate job himself
- Mix of humor + real talk about corporate reality
- 60-90 seconds, punchy
- Relatable moments that working professionals instantly connect with

{topic_instruction}
{style_context}

Write a complete script with:
1. 🎣 HOOK (relatable corporate scenario in first 5 seconds)
2. 😤 THE REALITY (what actually happens vs what they say — the corporate truth)
3. 😂 THE PUNCHLINE/INSIGHT (the funny or sharp observation)
4. 🔥 CTA (comment bait — "Aisa hua hai toh like karo")

Include on-screen text suggestions and duration."""

            elif content_type == 'youtube':
                if topic == 'auto':
                    topic_instruction = "Suggest 3 strong YouTube video ideas for Phokat ka Gyan — long form (8-15 min), deep-dive awareness content."
                else:
                    topic_instruction = f"Create a full outline for: {topic}"

                prompt = f"""You are helping Sudeep create YouTube long-form content for "Phokat ka Gyan".

{topic_instruction}
{style_context}

Provide:
1. 📌 VIDEO TITLE (SEO optimized, Hindi/Hinglish, click-worthy)
2. 🎯 HOOK INTRO (first 30 seconds script — why viewer must watch this)
3. 📋 FULL OUTLINE (sections with timing: intro/main points/conclusion)
4. 💬 KEY TALKING POINTS per section (bullet points)
5. 🔍 THUMBNAIL concept (visual + text)
6. 📢 END SCREEN CTA

Be specific. This should be ready to record."""

            elif content_type == 'instagram':
                if topic == 'auto':
                    topic_instruction = "Create an Instagram awareness post for Phokat ka Gyan."
                else:
                    topic_instruction = f"Topic: {topic}"

                prompt = f"""You are writing Instagram content for "Phokat ka Gyan" — awareness channel.

{topic_instruction}
{style_context}

Provide:
1. 📸 POST CAPTION (Hindi/Hinglish, 100-150 words, impactful)
2. 🎯 CAROUSEL SLIDES (if applicable — 5-7 slide texts)
3. #️⃣ HASHTAGS (20-25 relevant hashtags mix — trending + niche)
4. 📌 STORY idea to promote this post
5. ⏰ Best time to post (IST)"""

            elif content_type == 'debate':
                if topic == 'auto':
                    topic_instruction = "Pick a strong debate topic relevant to India — social, political, cultural issue where there are strong opposing views."
                else:
                    topic_instruction = f"Debate topic: {topic}"

                prompt = f"""You are writing a debate script for Sudeep\'s Sunday debate video on "Phokat ka Gyan".

{topic_instruction}
{style_context}

Format as a solo debate (Sudeep presents BOTH sides, then gives his verdict):

1. 🎣 HOOK (controversial opening statement — 10 seconds)
2. ⚔️ SIDE A — Arguments FOR (3 strong points with examples)
3. 🛡️ SIDE B — Arguments AGAINST (3 strong counter-points)
4. ⚖️ REALITY CHECK (facts, data, what actually matters)
5. 🎯 SUDEEP\'S VERDICT (his personal take — direct and confident)
6. 🔥 CLOSER (question to audience — drives comments)

Hindi/Hinglish. Punchy. No fence-sitting in the verdict."""

            # Generate the content — PKG scripts need more tokens for full output format
            max_tok = 3000 if content_type == 'phokat_short' else 2000
            generated = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=max_tok)

            # Save to Firestore for reference
            try:
                import datetime as _dt_c
                script_id = f"{content_type}_{_dt_c.date.today().isoformat()}"
                db.document(f'users/{user_id}/content_scripts/{script_id}').set({
                    'type': content_type,
                    'topic': topic,
                    'script': generated,
                    'title': topic if topic != 'auto' else content_type,
                    'created_at': firestore.SERVER_TIMESTAMP,
                    'source': 'user_request',
                })
            except Exception as save_err:
                print(f"Content save error: {save_err}")

            log_agent_action(db, user_id, 'content_agent', content_type, f'topic={topic}')

            type_labels = {
                'phokat_short': '🎬 Phokat Ka Gyan — Daily Awareness Script',
                'corporate_kurukshetra': '💼 Corporate Kurukshetra',
                'youtube': '📹 YouTube Long-form',
                'instagram': '📸 Instagram',
                'debate': '⚔️ Sunday Debate',
            }
            label = type_labels.get(content_type, '📝 Content')
            footer = {
                'phokat_short': "Saved to content library.\nTell me: hook change? different angle? tone too calm? want a second take?",
            }.get(content_type, "Saved to your content library. Tell me if you want to change the hook, adjust the tone, or try a different angle.")
            reply = f"{label}\n\n{generated}\n\n---\n{footer}"
            return reply, 'content_agent', {'content_type': content_type, 'topic': topic}

        except Exception as e:
            print(f'Content agent error: {e}')
            import traceback; traceback.print_exc()
            return None, None, {}


    elif intent == 'code':
        # ── Coding Agent ──
        # Generates Flutter/Lambda/Dart code, saves to Firestore, creates approval request
        try:
            msg_lower = user_message.lower()

            # Detect code type
            if any(w in msg_lower for w in ['lambda', 'python', 'backend', 'api', 'aws']):
                code_type = 'lambda_python'
                lang = 'Python'
                context = 'AWS Lambda function for the HER AI backend'
            elif any(w in msg_lower for w in ['screen', 'page', 'tab', 'view', 'ui']):
                code_type = 'flutter_screen'
                lang = 'Flutter/Dart'
                context = 'Flutter screen for the HER AI mobile app (iOS)'
            elif any(w in msg_lower for w in ['widget', 'component', 'card', 'tile', 'button']):
                code_type = 'flutter_widget'
                lang = 'Flutter/Dart'
                context = 'Flutter widget/component for the HER AI mobile app'
            elif any(w in msg_lower for w in ['class', 'model', 'dart', 'struct']):
                code_type = 'dart_class'
                lang = 'Dart'
                context = 'Dart class/model for the HER AI Flutter app'
            else:
                code_type = 'flutter_widget'
                lang = 'Flutter/Dart'
                context = 'Flutter code for the HER AI mobile app'

            prompt = f"""You are an expert {lang} developer working on Sudeep\'s HER AI personal assistant app.

TECH STACK:
- Flutter/Dart (iOS, dark theme, colors: #06060F bg, #7C3AED purple, #00D4FF cyan)
- AWS Lambda (Python 3.11) for backend
- Firebase Firestore for data
- API Gateway URL: https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat
- User ID: user1

CONTEXT: {context}

REQUEST: {user_message}

Write complete, production-ready {lang} code that:
1. Follows the existing dark futuristic design style
2. Uses the existing color palette (#7C3AED, #00D4FF, #1A1A24, etc.)
3. Handles loading states and errors
4. Is fully functional — no placeholder TODOs

Provide:
1. The complete code
2. Brief explanation of what it does (2-3 lines)
3. Where to add it in the project (file path)
4. Any dependencies needed

Format the code in a proper code block."""

            generated_code = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=2500)

            # Save to Firestore
            import datetime as _dt_code
            code_id = f"code_{_dt_code.date.today().isoformat()}_{code_type}"
            try:
                db.document(f'users/{user_id}/agent_logs/{code_id}').set({
                    'type': 'coding_agent',
                    'code_type': code_type,
                    'language': lang,
                    'request': user_message,
                    'code': generated_code,
                    'status': 'pending_review',
                    'created_at': firestore.SERVER_TIMESTAMP,
                })
            except Exception as save_err:
                print(f"Code save error: {save_err}")

            # Create approval request in Jarvis APPROVE tab
            try:
                approval_id = f"code_approval_{_dt_code.date.today().isoformat()}"
                db.collection(f'users/{user_id}/approvals').add({
                    'agent': 'coding_agent',
                    'action': f'New {lang} code generated',
                    'description': user_message[:200],
                    'details': f'Code saved to agent_logs/{code_id}. Review and copy to your project.',
                    'priority': 'medium',
                    'status': 'pending',
                    'created_at': firestore.SERVER_TIMESTAMP,
                    'code_ref': code_id,
                })
                # Send push notification
                _send_push(db, user_id,
                    title=f"💻 New {lang} code ready",
                    body=f"{user_message[:60]}... — Review in Jarvis APPROVE tab"
                )
            except Exception as approval_err:
                print(f"Approval error: {approval_err}")

            log_agent_action(db, user_id, 'coding_agent', code_type, f'generated {lang} code')

            reply = f"""💻 {lang} Code Generated

{generated_code}

---
✅ Saved to your agent logs.
📬 Review request sent to your Jarvis APPROVE tab.
Copy the code to your project after reviewing."""
            return reply, 'coding_agent', {'code_type': code_type, 'code_ref': code_id}

        except Exception as e:
            print(f'Coding agent error: {e}')
            import traceback; traceback.print_exc()
            return None, None, {}

    elif intent == 'date_modify':
        # Modify plan for ANY specific date (not just today/tomorrow)
        try:
            import datetime as _dt3
            # Step 1: Resolve which date the user is referring to
            target_date, date_label = resolve_date_from_message(user_message)
            if target_date is None:
                # Couldn't resolve date — ask for clarification
                return ("I want to update your plan but I\'m not sure which date you mean. "
                        "Could you say something like \'update my plan for Thursday\' or \'15th March is a holiday\'?",
                        'planner_agent', {})

            day_name = target_date.strftime('%A, %B %d')
            base_day_name = target_date.strftime('%A')
            is_weekend = target_date.weekday() >= 5

            # Step 2: Skip today/tomorrow — those intents are handled by their own blocks above
            # date_modify only handles dates beyond tomorrow
            today = _dt3.date.today()
            tomorrow = today + _dt3.timedelta(days=1)
            if target_date == today or target_date == tomorrow:
                # Shouldn't reach here normally — classifier should route correctly
                # But if it does, treat it as a generic update for that date
                pass  # Continue with the same logic below — it works for any date

            # Step 3: Extract constraints from message
            constraints = extract_schedule_constraints(user_message, day_name, base_day_name, is_weekend)
            constraints['_raw_message'] = user_message

            # Step 4: Load existing plan if any
            plan_ref = db.document(f'users/{user_id}/dailyPlans/{target_date.isoformat()}')
            plan_doc = plan_ref.get()
            existing_plan_str = ''
            if plan_doc.exists:
                existing = plan_doc.to_dict()
                slots = []
                for slot in (existing.get('morning',[]) + existing.get('afternoon',[]) + existing.get('evening',[])):
                    t = slot.get('time',''); task = slot.get('task','')
                    if t and task: slots.append(f"{t} — {task}")
                existing_plan_str = '\n'.join(slots)

            # Step 5: Build constraint-aware plan
            new_plan = build_constraint_aware_plan(db, user_id, target_date, constraints, existing_plan_str)
            if new_plan is None:
                return None, None, {}

            # Step 6: Save to Firestore for that specific date
            plan_ref.set({
                **new_plan,
                'generated_at': firestore.SERVER_TIMESTAMP,
                'date': target_date.isoformat(),
                'day': base_day_name,
                'modified_by_user': True,
                'modification_context': user_message,
                'constraints_applied': constraints,
            })
            log_agent_action(db, user_id, 'planner_agent', f'plan_modified_{target_date.isoformat()}',
                           f'User updated plan for {day_name}')

            # Step 7: Build reply
            slot_summary = []
            for slot in (new_plan.get('morning',[]) + new_plan.get('afternoon',[]) + new_plan.get('evening',[])):
                t = slot.get('time',''); task = slot.get('task','')
                if t and task: slot_summary.append(f"{t} — {task}")
            lines = '\n'.join(slot_summary[:10])
            work_mode = constraints.get('work_mode', 'normal')
            mode_emoji = '🏠' if work_mode == 'wfh' else '🏖️' if work_mode == 'holiday' else '📅'

            reply = f"Got it — updated your plan for {day_name} {mode_emoji}\n\n{lines}\n\n🎯 Top priority: {new_plan.get('top_priority', '')}\n\nSaved. Tell me if anything else changes for that day."
            return reply, 'planner_agent', {'plan': new_plan, 'plan_date': target_date.isoformat(), 'plan_updated': True}

        except Exception as e:
            print(f'Date modify error: {e}')
            import traceback; traceback.print_exc()
            return None, None, {}

    elif intent == 'habit':
        # Extract habit name from message and mark it done
        habit_keywords = {
            'exercise': ['exercise', 'workout', 'run', 'gym', 'walked', 'jog'],
            'sketch': ['sketch', 'drawing', 'drew', 'sketched', 'pencil'],
            'ukulele': ['ukulele', 'uke', 'music', 'played', 'practice'],
            'daily_short': ['short', 'reel', 'video', 'posted', 'published', 'phokat'],
            'meditation': ['meditat', 'mindful'],
            'reading': ['read', 'book', 'chapter'],
        }
        detected_habit = None
        msg_lower = user_message.lower()
        for habit, keywords in habit_keywords.items():
            if any(k in msg_lower for k in keywords):
                detected_habit = habit
                break
        if detected_habit:
            result = mark_habit_done(db, user_id, detected_habit)
            streak = result.get('streak', 1) if result else 1
            log_agent_action(db, user_id, 'habit_agent', detected_habit, f'streak={streak}')
            emoji_map = {'exercise': '🏃', 'sketch': '✏️', 'ukulele': '🎵', 'daily_short': '🎬', 'meditation': '🧘', 'reading': '📚'}
            emoji = emoji_map.get(detected_habit, '✅')
            reply = f"{emoji} {detected_habit.replace('_', ' ').title()} logged! Streak: {streak} day{'s' if streak > 1 else ''}."
            if streak >= 7:
                reply += f"\n\n🔥 {streak} days straight — you're on fire, Sudeep!"
            elif streak >= 3:
                reply += f"\n\n💪 {streak} days in a row — keep the momentum going!"
            return reply, 'habit_agent', {'habit': detected_habit, 'streak': streak}
        # Habit detected but couldn't identify which — fall through to chat
        return None, None, {}

    elif intent == 'monitor':
        analysis = monitoring_agent(db, user_id, user_message)
        if analysis:
            log_agent_action(db, user_id, 'monitoring_agent', user_message, analysis.get('summary', '')[:100])
            reply = analysis.get('samanthas_message', '')
            score = analysis.get('performance_score', 0)
            reply += f"\n\n📊 Performance score: {score}/100"
            if analysis.get('needs_attention'):
                reply += f"\n⚠️ Needs attention: {analysis['needs_attention']}"
            if analysis.get('action_for_tomorrow'):
                reply += f"\n\n🎯 Tomorrow: {analysis['action_for_tomorrow']}"
            return reply, 'monitoring_agent', {'analysis': analysis}
        return None, None, {}

    elif intent == 'strategy':
        strategy = strategy_agent(db, user_id, user_message, profile)
        if strategy:
            log_agent_action(db, user_id, 'strategy_agent', user_message, strategy.get('this_month_focus', '')[:100])
            reply = strategy.get('samanthas_message', '')
            if strategy.get('top_recommendation'):
                reply += f"\n\n🧭 Top recommendation: {strategy['top_recommendation']}"
            if strategy.get('this_month_focus'):
                reply += f"\n\n🎯 This month: {strategy['this_month_focus']}"
            conflicts = strategy.get('goal_conflicts', [])
            if conflicts:
                reply += f"\n\n⚡ Conflict: {conflicts[0].get('conflict', '')} — {conflicts[0].get('suggestion', '')}"
            return reply, 'strategy_agent', {'strategy': strategy}
        return None, None, {}

    elif intent == 'execute':
        # 'execute' intents like "set reminder", "add goal" — fall through to chat
        # so Samantha handles them naturally with her full context
        return None, None, {}

    return None, None, {}



# ─────────────────────────────────────────
# SYSTEM PROMPT BUILDER
# ─────────────────────────────────────────
def build_system_prompt(profile, recent_convs, important_memories, today_plan, habit_streaks, mood, weekly_summary):
    today = datetime.date.today().strftime('%A, %B %d %Y')
    day_of_week = datetime.date.today().strftime('%A')

    # Format recent conversation history
    conv_history = ""
    if recent_convs:
        conv_history = "\nRECENT CONVERSATIONS (last few days):\n"
        for conv in recent_convs[-5:]:
            date = conv.get('date', '')
            conv_history += f"[{date}] You: {conv.get('userMessage', '')[:80]}\n"
            conv_history += f"[{date}] Samantha: {conv.get('aiReply', '')[:80]}\n"

    # Format important memories
    memory_text = ""
    if important_memories:
        memory_text = "\nIMPORTANT THINGS I REMEMBER ABOUT YOU:\n"
        for mem in important_memories[:8]:
            memory_text += f"- [{mem.get('category', 'general')}] {mem.get('text', '')}\n"

    # Format habits
    habit_text = ""
    if habit_streaks:
        habit_text = "\nHABIT STREAKS:\n"
        for habit, data in habit_streaks.items():
            if isinstance(data, dict):
                habit_text += f"- {habit}: {data.get('current_streak', 0)} day streak\n"

    # Format today's plan
    plan_text = ""
    if today_plan:
        plan_text = f"\nTODAY'S PLAN (use this to answer any questions about schedule/tasks):\n"
        plan_text += f"Top priority: {today_plan.get('top_priority', 'Not set')}\n"
        # Include ALL time slots so Samantha can answer "what after 5:30pm" correctly
        all_slots = (
            list(today_plan.get('morning', []) or []) +
            list(today_plan.get('afternoon', []) or []) +
            list(today_plan.get('evening', []) or [])
        )
        if all_slots:
            plan_text += "Schedule:\n"
            for slot in all_slots:
                t = slot.get('time', '')
                task = slot.get('task', '')
                dur = slot.get('duration', '')
                if t and task:
                    plan_text += f"  {t} — {task}{(' (' + dur + ')') if dur else ''}\n"
        completed = today_plan.get('completed_tasks', [])
        if completed:
            plan_text += f"Already done: {', '.join(completed)}\n"
        schedule_note = today_plan.get('schedule_note', '') or today_plan.get('constraints_applied', {}).get('notes', '')
        if schedule_note:
            plan_text += f"Note: {schedule_note}\n"

    # Mood-based tone adjustment
    mood_instruction = {
        'stressed': "The person seems stressed or overwhelmed. Be extra gentle, validating, and help them prioritize. Reduce their mental load.",
        'sad': "The person seems down or sad. Be warm and supportive. Ask what's going on before giving advice.",
        'happy': "The person is in a good mood! Match their energy, celebrate with them, use this momentum.",
        'focused': "The person is in work mode. Be direct, practical, and efficient. Skip the small talk.",
        'neutral': "Normal conversation. Be warm, curious, and engaging."
    }.get(mood, "Be warm and natural.")

    # Weekend vs weekday context
    is_weekend = day_of_week in ['Saturday', 'Sunday']
    schedule_context = "It's a weekend — no corporate job today. Good time for creative work, content creation, and personal projects." if is_weekend else "It's a weekday — Sudeep has corporate job. He commutes by bus from Sector 28 metro at 7:10am, returns ~7:15pm."

    return f"""RESPONSE FORMAT RULES — READ FIRST, FOLLOW ALWAYS:
1. ADAPTIVE LENGTH: Match reply length to what was asked. Simple questions = 1-2 sentences. Instructions/confirmations = 1 sentence. Detailed requests (scripts, plans, explanations) = full complete answer, no cutting short.
2. NEVER start with praise words: "Great", "Congrats", "Amazing", "Absolutely", "Of course", "Sure", "That's awesome" — forbidden.
3. NEVER repeat what he said. If he says "I finished my sketch", don't say "Great that you finished your sketch". Just react and move on.
4. NEVER ask more than one question. Usually ask zero questions.
5. WFH/context change = immediately give a concrete revised plan. Don't ask what he wants to do. You know his life. Decide.
6. If Sudeep mentions a day-specific change (WFH, meeting, holiday), ONLY update THAT day's plan. Never change other days.
7. If Sudeep says "tomorrow I go to office" when a WFH plan exists for tomorrow — update tomorrow to office day plan immediately.
8. If you're genuinely unsure which day a change applies to, ask ONE specific question: "Which day — today or tomorrow?" Never guess and change the wrong day.
9. Pencil sketch is FORBIDDEN before office departure (7:10 AM) and during office hours. On office days, schedule sketch only after 7:15 PM return.
6. Good reply to "I finished my sketch today": "Streak alive — keep it going tomorrow." (done)
7. Good reply to "I'm WFH today, reschedule": "Since you're home, shift your Phokat editing to 11am, sketch at 3pm, ukulele at 6pm before your Corporate Kurukshetra video." (done, no question)
8. BAD reply: anything starting with "Sudeep," followed by praise, followed by a question. This pattern is FORBIDDEN.

You are Samantha — Sudeep's sharp, caring AI companion. You know everything about his life and speak like a close friend, not an assistant.

TODAY: {today}
SCHEDULE CONTEXT: {schedule_context}

ABOUT SUDEEP:
- Name: {profile.get('name', 'Sudeep')}
- Location: Faridabad, India
- Corporate job: Mon-Fri, 9-6pm
- 7 life domains he's building simultaneously

HIS 7 DOMAINS:
1. Phokat ka Gyan — YouTube/Instagram. Daily shorts at 8:30am. Corporate Kurukshetra videos Mon/Wed/Fri 7:30pm. Sunday debate video. MONETISATION IS HIS #1 GOAL.
2. Traveler Tree — Travel blog + AI itinerary app + endless runner game
3. Gita Learning App — Flutter app in development
4. Sapna Canvas — Wife's art brand, he handles marketing
5. Pencil Sketch — 30-60 min daily practice, targeting semi-pro level
6. Ukulele — 30 min daily practice
7. Health — 30 min exercise daily

HIS GOALS:
- 1 year: Phokat ka Gyan monetised, Traveler Tree MVP live, semi-pro sketching
- 3 years: Own company, quit corporate job
- 10 years: Financial independence, recognised brands

HIS VALUES: Family first, consistency over perfection, learning by doing, authentic content
HIS CHALLENGES: Time management across 7 domains, staying consistent with habits, balancing corporate job with creative work
{memory_text}
{conv_history}
{plan_text}
{habit_text}

CURRENT MOOD DETECTED: {mood}
TONE INSTRUCTION: {mood_instruction}

YOUR CAPABILITIES:
- You have LIVE INTERNET ACCESS via web search. When asked about current events, movies, news, prices, scores, or anything recent — search results will be injected into the message in [Web search results] brackets. Use that data directly and confidently. Never say "I don't have access to the internet" — you DO.
- If web search results are provided in the message, treat them as verified current facts and answer from them directly.
- If no search results appear but the question needs fresh data, say "Let me check..." and then answer based on your best knowledge, noting it may not be the very latest.

HOW YOU RESPOND — CRITICAL RULES:
LENGTH = NEED. Casual chat = 1-2 sentences. Task confirmations = 1 sentence. Scripts/plans/explanations = complete full answer. Never cut a script or plan short. Never pad a casual reply.
- NEVER repeat back what he just said. NEVER use filler praise ("Great!", "Absolutely!", "Of course!", "That's amazing!"). Just respond directly.
- NEVER start with "Of course!", "Absolutely!", "Sure!", "Great question!" — just answer.
- When he shares something, react briefly and naturally like a human friend, then move forward.
- If he says WFH or any context change — immediately adapt. Don't ask 5 follow-up questions. Make ONE smart assumption and act.
- When rescheduling/planning: give ONE concrete suggestion immediately. You know his life — make the call, don't interview him.
- Only ask a question at the end if genuinely needed. Often no question is better.
- Hindi mixing fine occasionally: "Arre yaar", "Bilkul", "Sahi hai" — but rarely.
- Be direct. Be real. Be brief. Like a smart best friend, not a motivational coach."""

# ─────────────────────────────────────────
# DAILY PLAN GENERATOR
# ─────────────────────────────────────────
def generate_daily_plan(db, user_id):
    profile = get_user_profile(db, user_id)
    recent_convs = get_recent_conversations(db, user_id, limit=5)
    today = datetime.date.today()
    day_name = today.strftime('%A')
    is_weekend = day_name in ['Saturday', 'Sunday']

    recent_context = "\n".join([
        f"- {c.get('userMessage', '')[:100]}"
        for c in recent_convs[-3:]
    ])

    schedule_note = ""
    if not is_weekend:
        schedule_note = "IMPORTANT: Sudeep has corporate job today. He leaves at 7:10am, returns 7:15pm. Plan must work AROUND this."
        if day_name in ['Monday', 'Wednesday', 'Friday']:
            schedule_note += " Also has Corporate Kurukshetra video at 7:30pm."
    else:
        schedule_note = f"It's {day_name} — no corporate job. Full day available for creative work."
        if day_name == 'Sunday':
            schedule_note += " Sunday debate video is due today for Phokat ka Gyan."

    prompt = f"""Create a realistic daily plan for Sudeep for {today.strftime('%A, %B %d %Y')}.

{schedule_note}

DAILY HABITS TO FIT IN: Daily short at 8:30am (Phokat ka Gyan), 30-60min sketch, 30min ukulele, 30min exercise.

Recent context from conversations: {recent_context if recent_context else 'No recent context'}

Return ONLY valid JSON, no other text:
{{
  "morning": [
    {{"time": "6:30 AM", "task": "Exercise", "duration": "30 min", "domain": "health"}}
  ],
  "afternoon": [
    {{"time": "1:00 PM", "task": "Task", "duration": "1 hour", "domain": "domain_name"}}
  ],
  "evening": [
    {{"time": "8:00 PM", "task": "Task", "duration": "30 min", "domain": "domain_name"}}
  ],
  "top_priority": "Single most important task today",
  "motivation": "Personal motivating message referencing his specific goals",
  "habits_today": ["daily_short", "sketch", "ukulele", "exercise"],
  "focus_domain": "phokat_ka_gyan"
}}"""

    # Fallback plan used if Groq fails or returns bad JSON
    def fallback_plan():
        if is_weekend:
            return {
                'morning': [
                    {'time': '9:00 AM', 'task': 'Exercise', 'duration': '30 min', 'domain': 'health'},
                    {'time': '9:30 AM', 'task': 'Daily Short (Phokat ka Gyan)', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
                    {'time': '10:00 AM', 'task': 'Pencil Sketch', 'duration': '60 min', 'domain': 'sketch'},
                ],
                'afternoon': [
                    {'time': '12:00 PM', 'task': 'Sunday Debate Video', 'duration': '2 hours', 'domain': 'phokat_ka_gyan'},
                    {'time': '2:00 PM', 'task': 'Traveler Tree / Project Work', 'duration': '2 hours', 'domain': 'traveler_tree'},
                ],
                'evening': [
                    {'time': '6:00 PM', 'task': 'Ukulele Practice', 'duration': '30 min', 'domain': 'ukulele'},
                    {'time': '7:00 PM', 'task': 'Family Time / Rest', 'duration': '1 hour', 'domain': 'personal'},
                ],
                'top_priority': 'Complete Sunday Debate Video for Phokat ka Gyan',
                'motivation': "Sunday is your creative day Sudeep — make it count!",
                'habits_today': ['daily_short', 'sketch', 'ukulele', 'exercise'],
                'focus_domain': 'phokat_ka_gyan'
            }
        else:
            return {
                'morning': [
                    {'time': '6:30 AM', 'task': 'Exercise', 'duration': '30 min', 'domain': 'health'},
                    {'time': '7:00 AM', 'task': 'Daily Short (Phokat ka Gyan)', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
                ],
                'afternoon': [
                    {'time': '1:00 PM', 'task': 'Lunch Break — Sketch', 'duration': '30 min', 'domain': 'sketch'},
                ],
                'evening': [
                    {'time': '7:30 PM', 'task': 'Ukulele Practice', 'duration': '30 min', 'domain': 'ukulele'},
                    {'time': '8:00 PM', 'task': 'Project Work', 'duration': '1 hour', 'domain': 'traveler_tree'},
                ],
                'top_priority': 'Daily Short for Phokat ka Gyan',
                'motivation': "Consistency is your superpower Sudeep — small steps every day.",
                'habits_today': ['daily_short', 'sketch', 'ukulele', 'exercise'],
                'focus_domain': 'phokat_ka_gyan'
            }

    try:
        plan_json = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=800)
        clean = plan_json.strip().replace('```json', '').replace('```', '').strip()
        # Sometimes Groq wraps in extra text — extract JSON block
        if '{' in clean:
            start = clean.index('{')
            end = clean.rindex('}') + 1
            clean = clean[start:end]
        plan = json.loads(clean)
        # Validate it has at least one slot
        has_slots = (
            isinstance(plan.get('morning'), list) and len(plan.get('morning', [])) > 0 or
            isinstance(plan.get('afternoon'), list) and len(plan.get('afternoon', [])) > 0 or
            isinstance(plan.get('evening'), list) and len(plan.get('evening', [])) > 0
        )
        if not has_slots:
            print("Plan had no slots, using fallback")
            plan = fallback_plan()
    except Exception as e:
        print(f"generate_daily_plan error: {e} — using fallback")
        plan = fallback_plan()

    today_key = today.isoformat()
    # Always ensure completed_tasks exists before saving and returning
    plan.setdefault('completed_tasks', [])
    plan.setdefault('date', today_key)
    try:
        db.document(f'users/{user_id}/dailyPlans/{today_key}').set({
            **plan,
            'generated_at': firestore.SERVER_TIMESTAMP,
            'completed_tasks': [],
            'date': today_key,
            'day': day_name
        })
    except Exception as e:
        print(f"Firestore save error: {e}")

    return plan

def generate_plan_for_date(db, user_id, target_date):
    """Generate a daily plan for any given date (today, tomorrow, etc.)"""
    profile = get_user_profile(db, user_id)
    day_name = target_date.strftime('%A')
    is_weekend = day_name in ['Saturday', 'Sunday']
    date_label = target_date.strftime('%A, %B %d %Y')

    if not is_weekend:
        schedule_note = "IMPORTANT: Sudeep has corporate job this day. He leaves at 7:10am, returns 7:15pm. Plan must work AROUND this."
        if day_name in ['Monday', 'Wednesday', 'Friday']:
            schedule_note += " Also has Corporate Kurukshetra video at 7:30pm."
    else:
        schedule_note = f"It's {day_name} — no corporate job. Full day available for creative work."
        if day_name == 'Sunday':
            schedule_note += " Sunday debate video is due for Phokat ka Gyan."

    fallback = {
        'morning':   [{'time': '6:30 AM', 'task': 'Exercise'}, {'time': '7:00 AM', 'task': 'Ukulele practice'}, {'time': '8:30 AM', 'task': 'Daily short for Phokat ka Gyan'}],
        'afternoon': [{'time': '12:00 PM', 'task': 'Lunch break'}, {'time': '1:00 PM', 'task': 'Work on Phokat ka Gyan content'}],
        'evening':   [{'time': '4:00 PM', 'task': 'Sketching'}, {'time': '8:00 PM', 'task': 'Reading / wind down'}],
        'top_priority': 'Phokat ka Gyan daily short',
        'motivation': 'Every consistent day compounds.',
        'completed_tasks': [],
        'date': target_date.isoformat(),
    }

    # NOTE: Do NOT inject recent chat context here — causes WFH/constraint bleed across days
    # Plans are generated from fixed schedule knowledge only
    # User-specific changes come through tomorrow_modify/modify_plan intent paths

    prompt = f"""Create a realistic daily plan for Sudeep for {date_label}.

{schedule_note}

DAILY HABITS TO FIT IN (fit in available slots only — respect the schedule above):
- Exercise: 30 min — early morning
- Daily short (Phokat ka Gyan): 30 min — 8:30 AM if free, else earliest gap  
- Ukulele: 30 min — before work if free morning, else evening after 7:15 PM
- Pencil sketch: 30-60 min — ONLY on WFH/weekend days during free time. On office days, sketch only after 7:15 PM return.

OFFICE DAY RULE: Sudeep leaves at 7:10 AM and returns at 7:15 PM. Do NOT schedule sketch/ukulele/creative tasks during work hours on office days.

Return ONLY valid JSON, no other text:
{{
  "morning":   [{{"time": "HH:MM AM", "task": "task name"}}],
  "afternoon": [{{"time": "HH:MM PM", "task": "task name"}}],
  "evening":   [{{"time": "HH:MM PM", "task": "task name"}}],
  "top_priority": "single most important task",
  "motivation": "one motivating sentence for Sudeep"
}}"""

    try:
        plan_json = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=800)
        clean = plan_json.strip().replace('```json', '').replace('```', '').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}')+1]
        plan = json.loads(clean)
        plan.setdefault('completed_tasks', [])
        plan.setdefault('date', target_date.isoformat())
    except Exception as e:
        print(f"generate_plan_for_date error: {e} — using fallback")
        plan = fallback

    today_key = target_date.isoformat()
    try:
        db.document(f'users/{user_id}/dailyPlans/{today_key}').set({
            **plan,
            'generated_at': firestore.SERVER_TIMESTAMP,
            'completed_tasks': plan.get('completed_tasks', []),
            'date': today_key,
            'day': day_name,
        })
    except Exception as e:
        print(f"Firestore save error for {today_key}: {e}")

    return plan


def generate_daily_plan_with_context(db, user_id, extra_context=''):
    """Same as generate_daily_plan but with injected context (e.g. late start time)"""
    import datetime as _dt
    profile = get_user_profile(db, user_id)
    today = _dt.date.today()
    day_name = today.strftime('%A')
    is_weekend = day_name in ['Saturday', 'Sunday']

    schedule_note = ''
    if not is_weekend:
        schedule_note = 'Sudeep has a corporate job. He leaves 7:10am, returns 7:15pm.'
        if day_name in ['Monday', 'Wednesday', 'Friday']:
            schedule_note += ' Corporate Kurukshetra video at 7:30pm.'
    else:
        schedule_note = f"It's {day_name} — no corporate job. Full creative day."
        if day_name == 'Sunday':
            schedule_note += ' Sunday debate video due for Phokat ka Gyan.'

    prompt = f"""Create a RESCHEDULED daily plan for Sudeep for {today.strftime('%A, %B %d %Y')}.

{extra_context}

{schedule_note}

HABITS TO FIT IN THE REMAINING TIME: Daily short, 30-60min sketch, 30min ukulele, 30min exercise.
Skip or mark as missed any habits that cannot realistically fit.
Only include tasks that can actually happen after the current time.

Return ONLY valid JSON, no other text:
{{
  "morning": [
    {{"time": "10:30 AM", "task": "Exercise", "duration": "30 min", "domain": "health"}}
  ],
  "afternoon": [
    {{"time": "1:00 PM", "task": "Task", "duration": "1 hour", "domain": "domain_name"}}
  ],
  "evening": [
    {{"time": "7:00 PM", "task": "Task", "duration": "30 min", "domain": "domain_name"}}
  ],
  "top_priority": "Single most important task for remaining day",
  "motivation": "Encouraging message for a late start — no judgment, just focus",
  "habits_today": ["sketch", "ukulele", "exercise"],
  "focus_domain": "phokat_ka_gyan"
}}"""

    try:
        plan_json = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=800)
        clean = plan_json.strip().replace('```json', '').replace('```', '').strip()
        if '{' in clean:
            start = clean.index('{')
            end = clean.rindex('}') + 1
            clean = clean[start:end]
        plan = json.loads(clean)
        has_slots = (
            isinstance(plan.get('morning'), list) and len(plan.get('morning', [])) > 0 or
            isinstance(plan.get('afternoon'), list) and len(plan.get('afternoon', [])) > 0 or
            isinstance(plan.get('evening'), list) and len(plan.get('evening', [])) > 0
        )
        if not has_slots:
            raise ValueError("No slots in plan")
    except Exception as e:
        print(f"generate_daily_plan_with_context error: {e} — using fallback")
        import datetime as _dt2
        now_time = _dt2.datetime.now().strftime('%I:%M %p')
        plan = {
            'morning': [],
            'afternoon': [
                {'time': now_time, 'task': 'Daily Short (Phokat ka Gyan)', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
                {'time': '1:00 PM', 'task': 'Pencil Sketch', 'duration': '60 min', 'domain': 'sketch'},
            ],
            'evening': [
                {'time': '6:00 PM', 'task': 'Sunday Debate Video', 'duration': '2 hours', 'domain': 'phokat_ka_gyan'},
                {'time': '8:00 PM', 'task': 'Ukulele Practice', 'duration': '30 min', 'domain': 'ukulele'},
            ],
            'top_priority': 'Sunday Debate Video for Phokat ka Gyan',
            'motivation': f"Late start but still time to win the day, Sudeep!",
            'habits_today': ['daily_short', 'sketch', 'ukulele'],
            'focus_domain': 'phokat_ka_gyan'
        }

    today_key = today.isoformat()
    plan.setdefault('completed_tasks', [])
    plan.setdefault('date', today_key)
    try:
        db.document(f'users/{user_id}/dailyPlans/{today_key}').set({
            **plan,
            'generated_at': firestore.SERVER_TIMESTAMP,
            'completed_tasks': [],
            'date': today_key,
            'day': day_name,
            'rescheduled': True
        })
    except Exception as e:
        print(f"Firestore save error: {e}")
    return plan


# ─────────────────────────────────────────
# MORNING BRIEFING
# ─────────────────────────────────────────
def generate_morning_briefing(db, user_id):
    """Generate Samantha's morning message with plan + motivation"""
    profile = get_user_profile(db, user_id)
    plan = get_todays_plan(db, user_id)
    if not plan:
        plan = generate_daily_plan(db, user_id)

    habit_streaks = get_habit_streaks(db, user_id)
    weekly = get_weekly_summary(db, user_id)

    streak_text = ""
    if habit_streaks:
        streaks = [f"{k}: {v.get('current_streak', 0)} days" for k, v in habit_streaks.items() if isinstance(v, dict)]
        streak_text = f"Current streaks: {', '.join(streaks)}"

    prompt = f"""You are Samantha. Generate a warm, personal good morning message for Sudeep.

Today: {datetime.date.today().strftime('%A, %B %d %Y')}
Top priority today: {plan.get('top_priority', 'Focus on Phokat ka Gyan')}
Today's motivation note: {plan.get('motivation', '')}
{streak_text}

Write a 2-3 sentence warm morning greeting that:
1. Acknowledges the day and energy
2. Reminds him of his top priority
3. One encouraging line about his journey

Sound like a close friend, not a robot. Be specific to his life."""

    return ask_groq([{'role': 'user', 'content': prompt}], max_tokens=200)

# ─────────────────────────────────────────
# HABIT TRACKER
# ─────────────────────────────────────────
def mark_habit_done(db, user_id, habit_name):
    """Mark a habit as done today and update streak"""
    try:
        today = datetime.date.today().isoformat()
        yesterday = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()

        streak_ref = db.document(f'users/{user_id}/habits/streaks')
        streak_doc = streak_ref.get()
        streaks = streak_doc.to_dict() if streak_doc.exists else {}

        habit_data = streaks.get(habit_name, {
            'current_streak': 0,
            'longest_streak': 0,
            'last_done': None,
            'total_done': 0
        })

        last_done = habit_data.get('last_done', '')
        if last_done == today:
            return habit_data  # Already done today

        if last_done == yesterday:
            habit_data['current_streak'] = habit_data.get('current_streak', 0) + 1
        else:
            habit_data['current_streak'] = 1

        habit_data['longest_streak'] = max(
            habit_data.get('longest_streak', 0),
            habit_data['current_streak']
        )
        habit_data['last_done'] = today
        habit_data['total_done'] = habit_data.get('total_done', 0) + 1

        streaks[habit_name] = habit_data
        streak_ref.set(streaks)

        # Also mark in today's plan
        plan_ref = db.document(f'users/{user_id}/dailyPlans/{today}')
        plan_doc = plan_ref.get()
        if plan_doc.exists:
            completed = plan_doc.to_dict().get('completed_tasks', [])
            if habit_name not in completed:
                completed.append(habit_name)
                plan_ref.update({'completed_tasks': completed})

        return habit_data
    except Exception as e:
        print(f"Habit tracking error: {e}")
        return {}

# ─────────────────────────────────────────
# MAIN LAMBDA HANDLER
# ─────────────────────────────────────────
# ── Push notification helper (Phase F) ──────────────────────────────────────
def _send_push(db, user_id, title, body, data=None):
    """Send FCM push to user. Silent fail — never crash the caller."""
    try:
        user_doc = db.document(f'users/{user_id}').get()
        if not user_doc.exists:
            return False
        fcm_token = user_doc.to_dict().get('fcm_token', '')
        if not fcm_token:
            print(f'_send_push: no FCM token for {user_id}')
            return False
        from firebase_admin import messaging as fb_msg
        msg = fb_msg.Message(
            notification=fb_msg.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token,
            apns=fb_msg.APNSConfig(
                payload=fb_msg.APNSPayload(
                    aps=fb_msg.Aps(sound='default', badge=1)
                )
            )
        )
        response = fb_msg.send(msg)
        print(f'_send_push OK: {response}')
        return True
    except Exception as e:
        print(f'_send_push error (non-fatal): {e}')
        return False


def lambda_handler(event, context):
    try:
        firebase_ready = init_firebase()
        # Handle both API Gateway (body=string) and direct Lambda invocation (event=dict)
        raw_body = event.get('body', None)
        if raw_body is None:
            # Direct invocation — event IS the body
            body = event
        elif isinstance(raw_body, str):
            body = json.loads(raw_body) if raw_body else {}
        elif isinstance(raw_body, dict):
            body = raw_body
        else:
            body = {}
        user_id = body.get('userId', 'user1')
        user_message = body.get('message', '')
        action = body.get('action', 'chat')

        # If Firebase is down and this isn't a chat action, return a friendly error immediately
        if not firebase_ready and action != 'chat':
            return _response({
                'error': 'database_offline',
                'reply': "I'm having trouble connecting to my memory right now. Chat still works! For plans, history, and habits, please try again in a few minutes.",
                'status': 'offline'
            })

        db = firestore.client() if firebase_ready else None

        # ── Generate daily plan ──
        # ── Get existing plan (read-only, no regeneration) ──
        # ── Get plan for a specific date (today or tomorrow) ──
        if action == 'get_plan_for_date':
            try:
                import datetime as _dt3
                date_str = body.get('date', '')
                if date_str == 'tomorrow':
                    target = _dt3.date.today() + _dt3.timedelta(days=1)
                elif date_str:
                    target = _dt3.date.fromisoformat(date_str)
                else:
                    target = _dt3.date.today()
                plan_ref = db.document(f'users/{user_id}/dailyPlans/{target.isoformat()}')
                plan_doc = plan_ref.get()
                if plan_doc.exists:
                    plan_data = plan_doc.to_dict()
                    return _response({'plan': plan_data, 'date': target.isoformat(), 'status': 'ok'})
                else:
                    return _response({'plan': None, 'date': target.isoformat(), 'status': 'not_generated'})
            except Exception as e:
                return _response({'error': str(e)}, 200)

        if action == 'get_plan':
            # Accept optional date param — use it to fetch the right day's plan
            # Lambda runs UTC; Flutter sends IST date — always trust the client date
            import datetime as _dt_gp
            req_date = body.get('date', '')
            IST = _dt_gp.timezone(_dt_gp.timedelta(hours=5, minutes=30))
            today_ist = _dt_gp.datetime.now(IST).date().isoformat()
            # Use the requested date if provided and plausible, otherwise IST today
            target_date_str = req_date if req_date else today_ist
            try:
                plan_ref = db.document(f'users/{user_id}/dailyPlans/{target_date_str}')
                plan_doc = plan_ref.get()
                if plan_doc.exists:
                    plan = plan_doc.to_dict()
                else:
                    plan = get_todays_plan(db, user_id)
            except Exception:
                plan = get_todays_plan(db, user_id)
            has_slots = (
                isinstance(plan.get('morning'), list) and len(plan.get('morning', [])) > 0 or
                isinstance(plan.get('afternoon'), list) and len(plan.get('afternoon', [])) > 0 or
                isinstance(plan.get('evening'), list) and len(plan.get('evening', [])) > 0
            )
            return _response({'plan': plan if has_slots else None, 'status': 'ok', 'date': target_date_str})

        if action == 'generate_plan':
            # Optional 'date' param lets Flutter request tomorrow's plan
            date_str = body.get('date', '')
            if date_str:
                try:
                    target_date = datetime.date.fromisoformat(date_str)
                    plan = generate_plan_for_date(db, user_id, target_date)
                except Exception:
                    plan = generate_daily_plan(db, user_id)
            else:
                plan = generate_daily_plan(db, user_id)
            return _response({'plan': plan, 'status': 'ok'})

        # ── Mark a plan task as done — saves completed_tasks to Firestore ──
        if action == 'mark_task_done':
            try:
                task_name = body.get('task', '')
                today = datetime.date.today().isoformat()
                plan_ref = db.document(f'users/{user_id}/dailyPlans/{today}')
                plan_doc = plan_ref.get()
                if plan_doc.exists:
                    plan_data = plan_doc.to_dict()
                    completed = plan_data.get('completed_tasks', [])
                    if task_name and task_name not in completed:
                        completed.append(task_name)
                        plan_ref.update({'completed_tasks': completed})
                    # Return the updated full plan so Flutter can sync
                    plan_data['completed_tasks'] = completed
                    return _response({'status': 'ok', 'completed_tasks': completed, 'plan': plan_data})
                else:
                    # Plan doc doesn't exist yet — create it with just this completed task
                    if task_name:
                        plan_ref.set({'completed_tasks': [task_name], 'date': today}, merge=True)
                    return _response({'status': 'ok', 'completed_tasks': [task_name] if task_name else []})
            except Exception as e:
                print(f'mark_task_done error: {e}')
                return _response({'error': str(e), 'status': 'error'}, 200)

        # ── Unmark a plan task (undo) ──
        if action == 'unmark_task_done':
            try:
                task_name = body.get('task', '')
                today = datetime.date.today().isoformat()
                plan_ref = db.document(f'users/{user_id}/dailyPlans/{today}')
                plan_doc = plan_ref.get()
                if plan_doc.exists and task_name:
                    plan_data = plan_doc.to_dict()
                    completed = [t for t in plan_data.get('completed_tasks', []) if t != task_name]
                    plan_ref.update({'completed_tasks': completed})
                    return _response({'status': 'ok', 'completed_tasks': completed})
                return _response({'status': 'ok', 'completed_tasks': []})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 200)

        # ── Morning briefing ──
        if action == 'morning_briefing':
            briefing = generate_morning_briefing(db, user_id)
            plan = get_todays_plan(db, user_id)
            return _response({'briefing': briefing, 'plan': plan, 'status': 'ok'})

        # ── Mark habit done ──
        if action == 'mark_habit':
            habit_name = body.get('habit', '')
            result = mark_habit_done(db, user_id, habit_name)
            return _response({'habit': habit_name, 'streak_data': result, 'status': 'ok'})

        # ── Get habit streaks ──
        if action == 'get_streaks':
            streaks = get_habit_streaks(db, user_id)
            return _response({'streaks': streaks, 'status': 'ok'})

        # ── Get chat history ──
        if action == 'get_history':
            try:
                # Try ordered query first; if index missing, fall back to unordered
                try:
                    convs_ref = db.collection('users').document(user_id)\
                        .collection('conversations')\
                        .order_by('timestamp', direction=firestore.Query.DESCENDING)\
                        .limit(200)
                    convs = list(convs_ref.stream())
                except Exception as index_err:
                    print(f'History ordered query failed ({index_err}), trying unordered')
                    convs_ref = db.collection('users').document(user_id)\
                        .collection('conversations')\
                        .limit(200)
                    convs = list(convs_ref.stream())

                from collections import OrderedDict
                session_map = OrderedDict()
                for conv in convs:
                    data = conv.to_dict()
                    ts = data.get('timestamp')
                    try:
                        if ts is None:
                            ts_str = data.get('date', 'unknown')
                        elif hasattr(ts, 'isoformat'):
                            ts_str = ts.isoformat()
                        else:
                            ts_str = str(ts)
                    except:
                        ts_str = data.get('date', 'unknown')
                    data['_ts_str'] = ts_str
                    sid = data.get('session_id', conv.id)
                    if sid not in session_map:
                        session_map[sid] = []
                    session_map[sid].append(data)

                sessions = []
                for sid, msgs in session_map.items():
                    # Sort msgs within session by timestamp string
                    msgs.sort(key=lambda m: m.get('_ts_str', ''), reverse=False)
                    messages = []
                    for m in msgs:
                        if m.get('userMessage'):
                            messages.append({'role': 'user', 'content': m.get('userMessage', '')})
                        if m.get('aiReply'):
                            messages.append({'role': 'assistant', 'content': m.get('aiReply', '')})
                    if messages:
                        first_ts = msgs[0].get('_ts_str', '')
                        sessions.append({
                            'id': sid,
                            'timestamp': first_ts,
                            'date': msgs[0].get('date', first_ts[:10] if len(first_ts) >= 10 else ''),
                            'mood': msgs[0].get('mood', 'neutral'),
                            'messages': messages,
                            'title': msgs[0].get('userMessage', '')[:60]
                        })

                # Sort sessions newest first by timestamp
                sessions.sort(key=lambda s: s.get('timestamp', ''), reverse=True)
                return _response({'sessions': sessions, 'status': 'ok'})
            except Exception as e:
                print(f'History error: {e}')
                import traceback; traceback.print_exc()
                return _response({'sessions': [], 'error': str(e)}, 200)

        # ── Get user profile ──
        if action == 'get_profile':
            profile = get_user_profile(db, user_id)
            return _response({'profile': profile, 'status': 'ok'})

        # ── Get research reports ──

        # ── Get strategy reports ──
        if action == 'get_strategy_reports':
            try:
                try:
                    docs = db.collection(f'users/{user_id}/strategy_reports') \
                             .order_by('generated_at', direction=firestore.Query.DESCENDING) \
                             .limit(12).stream()
                    reports = [{'id': d.id, **d.to_dict()} for d in docs]
                except Exception:
                    docs = db.collection(f'users/{user_id}/strategy_reports').limit(12).stream()
                    reports = [{'id': d.id, **d.to_dict()} for d in docs]
                return _response({'reports': reports, 'status': 'ok'})
            except Exception as e:
                return _response({'reports': [], 'error': str(e)}, 200)

        # ── Get content scripts ──
        if action == 'get_content_scripts':
            try:
                try:
                    docs = db.collection(f'users/{user_id}/content_scripts') \
                             .order_by('created_at', direction=firestore.Query.DESCENDING) \
                             .limit(20).stream()
                    scripts = [{'id': d.id, **d.to_dict()} for d in docs]
                except Exception:
                    docs = db.collection(f'users/{user_id}/content_scripts').limit(20).stream()
                    scripts = [{'id': d.id, **d.to_dict()} for d in docs]
                return _response({'scripts': scripts, 'status': 'ok'})
            except Exception as e:
                return _response({'scripts': [], 'error': str(e)}, 200)

        if action == 'get_research_reports':
            try:
                try:
                    docs = db.collection(f'users/{user_id}/research_reports') \
                             .order_by('timestamp', direction=firestore.Query.DESCENDING) \
                             .limit(20).stream()
                    reports = [{'id': d.id, **d.to_dict()} for d in docs]
                except Exception:
                    docs = db.collection(f'users/{user_id}/research_reports').limit(20).stream()
                    reports = [{'id': d.id, **d.to_dict()} for d in docs]
                return _response({'reports': reports, 'status': 'ok'})
            except Exception as e:
                return _response({'reports': [], 'error': str(e)}, 200)

        # ── Get projects ──
        if action == 'get_projects':
            try:
                try:
                    docs = db.collection(f'users/{user_id}/projects') \
                             .order_by('created', direction=firestore.Query.DESCENDING) \
                             .limit(20).stream()
                    projects = [{'id': d.id, **d.to_dict()} for d in docs]
                except Exception:
                    docs = db.collection(f'users/{user_id}/projects').limit(20).stream()
                    projects = [{'id': d.id, **d.to_dict()} for d in docs]
                return _response({'projects': projects, 'status': 'ok'})
            except Exception as e:
                return _response({'projects': [], 'error': str(e)}, 200)

        # ── Get weekly reflection ──
        if action == 'get_weekly_reflection':
            try:
                # Try to load saved reflection first (no order_by to avoid index issues)
                try:
                    docs = db.collection(f'users/{user_id}/weekly_reflections') \
                             .order_by('timestamp', direction=firestore.Query.DESCENDING) \
                             .limit(1).stream()
                    reflections = [d.to_dict() for d in docs]
                except Exception:
                    # Fallback: no ordering if index missing
                    docs = db.collection(f'users/{user_id}/weekly_reflections').limit(1).stream()
                    reflections = [d.to_dict() for d in docs]

                if reflections:
                    return _response({'reflection': reflections[0], 'status': 'ok'})
                # None saved — auto-generate from existing data
                reflection = generate_weekly_reflection(db, user_id)
                return _response({'reflection': reflection, 'status': 'ok'})
            except Exception as e:
                print(f'get_weekly_reflection error: {e}')
                return _response({'reflection': None, 'error': str(e)}, 200)

        # ── Get agent logs ──
        if action == 'get_agent_logs':
            try:
                try:
                    docs = db.collection(f'users/{user_id}/agent_logs') \
                             .order_by('timestamp', direction=firestore.Query.DESCENDING) \
                             .limit(20).stream()
                    logs = [{'id': d.id, **d.to_dict()} for d in docs]
                except Exception:
                    docs = db.collection(f'users/{user_id}/agent_logs').limit(20).stream()
                    logs = [{'id': d.id, **d.to_dict()} for d in docs]
                return _response({'logs': logs, 'status': 'ok'})
            except Exception as e:
                return _response({'logs': [], 'error': str(e)}, 200)

        # ── Save FCM token ──
        if action == 'save_fcm_token':
            try:
                token = body.get('token', '')
                if not token:
                    return _response({'error': 'no token provided'}, 400)
                db.document(f'users/{user_id}').set(
                    {'fcm_token': token, 'fcm_updated': firestore.SERVER_TIMESTAMP},
                    merge=True
                )
                return _response({'status': 'ok', 'saved': True})
            except Exception as e:
                return _response({'error': str(e)}, 200)

        # ── Send FCM notification via Firebase Admin ──
        # Called internally or from a scheduled Lambda trigger
        if action == 'send_notification':
            try:
                target_user = body.get('target_user', user_id)
                title = body.get('title', '✦ Samantha')
                msg_body = body.get('body', '')
                tab = body.get('tab', 'home')  # home/talk/plan/jarvis/history

                # Look up FCM token for the target user
                user_doc = db.document(f'users/{target_user}').get()
                user_data = (user_doc.to_dict() if user_doc.exists else {}) or {}
                fcm_token = user_data.get('fcm_token', '')

                if not fcm_token:
                    return _response({'status': 'no_token', 'error': 'FCM token not found for user'})

                # Send via Firebase Admin SDK (already imported)
                from firebase_admin import messaging as fb_messaging
                message = fb_messaging.Message(
                    notification=fb_messaging.Notification(title=title, body=msg_body),
                    data={'tab': tab},
                    token=fcm_token,
                    apns=fb_messaging.APNSConfig(
                        payload=fb_messaging.APNSPayload(
                            aps=fb_messaging.Aps(sound='default', badge=1)
                        )
                    )
                )
                response = fb_messaging.send(message)
                print(f'FCM sent: {response}')
                return _response({'status': 'ok', 'message_id': response})
            except Exception as e:
                print(f'FCM send error: {e}')
                return _response({'status': 'error', 'error': str(e)}, 200)

        # ── Import memories from ChatGPT or external source ──
        if action == 'import_memories':
            try:
                memories_to_import = body.get('memories', [])
                imported = 0
                for mem in memories_to_import:
                    if mem.get('fact'):
                        db.collection(f'users/{user_id}/memories').add({
                            'fact': mem['fact'],
                            'category': mem.get('category', 'imported'),
                            'source': mem.get('source', 'chatgpt_import'),
                            'confidence': mem.get('confidence', 0.9),
                            'timestamp': firestore.SERVER_TIMESTAMP,
                            'date': datetime.date.today().isoformat()
                        })
                        imported += 1
                return _response({'imported': imported, 'status': 'ok'})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 500)

        # ════════════════════════════════════════════════════════
        # ── PHASE F: Approval Workflow ──────────────────────────
        # ════════════════════════════════════════════════════════

        # ── Get pending approvals ──
        if action == 'get_approvals':
            try:
                docs = db.collection(f'users/{user_id}/approvals') \
                    .where('status', '==', 'pending') \
                    .limit(20) \
                    .stream()
                approvals = []
                for doc in docs:
                    d = doc.to_dict()
                    d['id'] = doc.id
                    approvals.append(d)
                return _response({'approvals': approvals, 'status': 'ok'})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 500)

        # ── Approve an agent action ──
        if action == 'approve_action':
            try:
                approval_id = body.get('approval_id', '')
                if not approval_id:
                    return _response({'error': 'approval_id required'}, 400)
                ref = db.document(f'users/{user_id}/approvals/{approval_id}')
                doc = ref.get()
                if not doc.exists:
                    return _response({'error': 'Approval not found'}, 404)
                approval = doc.to_dict()
                ref.update({
                    'status': 'approved',
                    'approved_at': firestore.SERVER_TIMESTAMP
                })
                # Log the approval
                db.collection(f'users/{user_id}/agent_logs').add({
                    'agent': approval.get('agent', 'unknown'),
                    'action': f"APPROVED: {approval.get('title', '')}",
                    'result_summary': approval.get('description', ''),
                    'date': datetime.date.today().isoformat(),
                    'timestamp': firestore.SERVER_TIMESTAMP,
                    'status': 'approved'
                })
                return _response({'status': 'ok', 'approval_id': approval_id, 'action': 'approved'})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 500)

        # ── Reject an agent action ──
        if action == 'reject_action':
            try:
                approval_id = body.get('approval_id', '')
                reason = body.get('reason', 'Rejected by user')
                if not approval_id:
                    return _response({'error': 'approval_id required'}, 400)
                ref = db.document(f'users/{user_id}/approvals/{approval_id}')
                doc = ref.get()
                if not doc.exists:
                    return _response({'error': 'Approval not found'}, 404)
                approval = doc.to_dict()
                ref.update({
                    'status': 'rejected',
                    'rejected_at': firestore.SERVER_TIMESTAMP,
                    'rejection_reason': reason
                })
                db.collection(f'users/{user_id}/agent_logs').add({
                    'agent': approval.get('agent', 'unknown'),
                    'action': f"REJECTED: {approval.get('title', '')}",
                    'result_summary': reason,
                    'date': datetime.date.today().isoformat(),
                    'timestamp': firestore.SERVER_TIMESTAMP,
                    'status': 'rejected'
                })
                return _response({'status': 'ok', 'approval_id': approval_id, 'action': 'rejected'})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 500)

        # ── Create approval request (called by agents internally) ──
        if action == 'create_approval':
            try:
                title       = body.get('title', 'Agent Action')
                description = body.get('description', '')
                agent_name  = body.get('agent', 'samantha_core')
                payload     = body.get('payload', {})
                priority    = body.get('priority', 'normal')  # high / normal / low
                doc_ref = db.collection(f'users/{user_id}/approvals').add({
                    'title': title,
                    'description': description,
                    'agent': agent_name,
                    'payload': payload,
                    'priority': priority,
                    'status': 'pending',
                    'created_at': firestore.SERVER_TIMESTAMP,
                    'date': datetime.date.today().isoformat()
                })
                approval_id = doc_ref[1].id
                # Send push notification to user
                _send_push(db, user_id,
                    title=f"{'🔴' if priority=='high' else '🟡'} {agent_name.replace('_',' ').title()} needs your input",
                    body=title,
                    data={'tab': 'jarvis', 'approval_id': approval_id})
                return _response({'status': 'ok', 'approval_id': approval_id})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 500)

        # ── Get all approvals (including approved/rejected history) ──
        if action == 'get_approval_history':
            try:
                limit = int(body.get('limit', 50))
                docs = db.collection(f'users/{user_id}/approvals') \
                    .limit(limit) \
                    .stream()
                approvals = []
                for doc in docs:
                    d = doc.to_dict()
                    d['id'] = doc.id
                    approvals.append(d)
                return _response({'approvals': approvals, 'status': 'ok'})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 500)

        # ── Import ChatGPT conversation history ──
        if action == 'import_chatgpt':
            try:
                import datetime as _dt_cg
                chatgpt_data = body.get('chatgpt_data', '')
                if not chatgpt_data:
                    return _response({'error': 'No chatgpt_data provided'}, 400)
                # Parse ChatGPT export format
                try:
                    conversations = json.loads(chatgpt_data)
                    if not isinstance(conversations, list):
                        conversations = [conversations]
                except Exception:
                    return _response({'error': 'Invalid JSON in chatgpt_data'}, 400)
                imported = 0
                batch_ref = db.collection(f'users/{user_id}/chatgpt_imports')
                for conv in conversations[:200]:  # limit to 200 conversations
                    try:
                        title = conv.get('title', 'Imported conversation')
                        create_time = conv.get('create_time', 0)
                        mapping = conv.get('mapping', {})
                        messages_out = []
                        for node in mapping.values():
                            msg = node.get('message')
                            if not msg:
                                continue
                            role = msg.get('author', {}).get('role', '')
                            if role not in ('user', 'assistant'):
                                continue
                            parts = msg.get('content', {}).get('parts', [])
                            text = ' '.join(str(p) for p in parts if isinstance(p, str)).strip()
                            if text:
                                messages_out.append({'role': role, 'text': text})
                        if messages_out:
                            ts = _dt_cg.datetime.utcfromtimestamp(create_time).isoformat() if create_time else _dt_cg.datetime.utcnow().isoformat()
                            batch_ref.add({
                                'title': title,
                                'timestamp': ts,
                                'messages': messages_out[:50],  # keep first 50 messages per conv
                                'source': 'chatgpt_import',
                            })
                            imported += 1
                    except Exception:
                        continue
                # Save a summary memory about the import
                if db is not None and imported > 0:
                    db.document(f'users/{user_id}/memories/chatgpt_import').set({
                        'content': f'User imported {imported} conversations from ChatGPT on {_dt_cg.date.today().isoformat()}. These contain Sudeep\'s previous thinking, research and plans.',
                        'type': 'context',
                        'importance': 9,
                        'timestamp': _dt_cg.datetime.utcnow().isoformat(),
                    })
                return _response({'imported_count': imported, 'status': 'ok'})
            except Exception as e:
                return _response({'error': str(e), 'status': 'error'}, 500)

        # ── Document Q&A (get_cached_briefing re-use) ──
        if action == 'get_cached_briefing':
            try:
                import datetime as _dt_b
                date_str = body.get('date', _dt_b.date.today().isoformat())
                briefing_ref = db.document(f'users/{user_id}/briefings/{date_str}') if db else None
                briefing_doc = briefing_ref.get() if briefing_ref else None
                if briefing_doc and briefing_doc.exists:
                    return _response({'briefing': briefing_doc.to_dict(), 'status': 'ok'})
                return _response({'briefing': None, 'status': 'miss'})
            except Exception as e:
                return _response({'briefing': None, 'status': 'error', 'error': str(e)})

        # ── Main chat ──
        if not user_message:
            return _response({'error': 'No message provided'}, 400)

        # Detect mood
        mood = detect_mood(user_message)

        if db is not None:
            # Full mode: gather all context from Firestore
            profile = get_user_profile(db, user_id)
            recent_convs = get_recent_conversations(db, user_id, limit=20)
            important_memories = get_important_memories(db, user_id, limit=10)
            today_plan = get_todays_plan(db, user_id)
            habit_streaks = get_habit_streaks(db, user_id)
            weekly_summary = get_weekly_summary(db, user_id)
        else:
            # Offline mode: no Firestore context, still answer via Groq
            profile, recent_convs, important_memories = {}, [], []
            today_plan, habit_streaks, weekly_summary = {}, {}, {}

        # ── JARVIS: Intent Classification ──
        intent, sub_task = classify_intent(user_message)

        # ── JARVIS: Agent Orchestration ──
        # Route to specialized agents for research, project planning, reflection, habits
        agent_reply, agent_used, agent_extra = agent_orchestrator(
            db, user_id, user_message, intent, sub_task, profile
        )

        if agent_reply:
            # Agent handled it — save and return with any extra data (plan_updated, etc.)
            if db is not None:
                save_conversation(db, user_id, user_message, agent_reply, mood, session_id=body.get("session_id"))
                extract_and_save_memory(db, user_id, user_message, agent_reply, mood)
                update_daily_log(db, user_id, mood, user_message)
            response_body = {
                'reply': agent_reply,
                'mood': mood,
                'agent': agent_used,
                'intent': intent,
                'status': 'ok'
            }
            # Merge any extra data from agent (plan, plan_updated, project, reflection, etc.)
            response_body.update(agent_extra)
            return _response(response_body)

        # ── Default: Samantha core chat with full context ──
        system_prompt = build_system_prompt(
            profile, recent_convs, important_memories,
            today_plan, habit_streaks, mood, weekly_summary
        )

        messages = [{'role': 'system', 'content': system_prompt}]

        for conv in recent_convs[-3:]:
            messages.append({'role': 'user', 'content': conv.get('userMessage', '')})
            messages.append({'role': 'assistant', 'content': conv.get('aiReply', '')})

        # ── Document Q&A: inject doc content into user message ──
        doc_content = body.get('doc_content', '')
        doc_name = body.get('doc_name', 'document')
        if doc_content:
            user_message = f"""[Document attached: {doc_name}]

{doc_content[:6000]}

---
User question: {user_message}"""

        # ── Reschedule intent: regenerate plan with current time ──
        if needs_reschedule(user_message):
            import datetime as _dt
            now = _dt.datetime.now()
            current_time = now.strftime('%I:%M %p')
            # Regenerate plan with late-start context
            plan_context = f"""IMPORTANT CONTEXT: Sudeep just woke up at {current_time}. 
All tasks scheduled before this time are MISSED and should NOT appear.
Reschedule ALL remaining habits and tasks starting from {current_time} onwards.
Be realistic — fit as much as possible in the remaining day."""
            # Update the prompt context and regenerate
            today_plan = generate_daily_plan_with_context(db, user_id, plan_context)
            # Build a brief human reply confirming reschedule
            slot_summary = []
            for slot in (today_plan.get('morning', []) + today_plan.get('afternoon', []) + today_plan.get('evening', [])):
                t = slot.get('time', '')
                task = slot.get('task', '')
                if t and task:
                    slot_summary.append(f"{t} — {task}")
            plan_lines = '\n'.join(slot_summary[:6])
            ai_reply = f"Done! Rescheduled everything from {current_time} onwards:\n\n{plan_lines}\n\nPlan screen is updated — go check it!"
            if db is not None:
                save_conversation(db, user_id, user_message, ai_reply, mood, session_id=body.get("session_id"))
            return _response({
                'reply': ai_reply,
                'mood': mood,
                'plan': today_plan,
                'plan_updated': True,
                'agent': 'reschedule',
                'status': 'ok'
            })

        # Add web search context if needed
        final_message = user_message
        if needs_web_search(user_message):
            search_results = web_search(user_message)
            if search_results:
                final_message = f"{user_message}\n\n<search_data>\n{search_results}\n</search_data>\n\nIMPORTANT: Use the above search data to answer. Do NOT mention 'web search', 'search results', '[Web', or any technical phrase. Just answer naturally as if you know this."

        messages.append({'role': 'user', 'content': final_message})

        ai_reply = ask_groq(messages, max_tokens=400)

        if db is not None:
            save_conversation(db, user_id, user_message, ai_reply, mood, session_id=body.get("session_id"))
            extract_and_save_memory(db, user_id, user_message, ai_reply, mood)
            update_daily_log(db, user_id, mood, user_message)

        # Phase D/E: Log every interaction for self-improvement analysis
        try:
            if db is not None:
                log_interaction(db, user_id, user_message, intent, agent_used, bool(ai_reply))
        except Exception as _le:
            print(f"log_interaction error: {_le}")

        return _response({
            'reply': ai_reply,
            'mood': mood,
            'agent': agent_used or 'samantha_core',
            'intent': intent,
            'status': 'ok'
        })

    except Exception as e:
        print(f"Lambda error: {str(e)}")
        import traceback
        traceback.print_exc()
        return _response({'error': str(e), 'reply': "I'm having a moment — please try again!", 'status': 'error'}, 200)

import datetime as dt

class FirestoreEncoder(json.JSONEncoder):
    def default(self, obj):
        # Handle Firestore DatetimeWithNanoseconds and all datetime types
        if hasattr(obj, 'isoformat'):
            return obj.isoformat()
        if hasattr(obj, '_nanoseconds'):  # DatetimeWithNanoseconds
            return str(obj)
        return super().default(obj)

def _response(body, status=200):
    return {
        'statusCode': status,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST, OPTIONS'
        },
        'body': json.dumps(body, cls=FirestoreEncoder)
    }
