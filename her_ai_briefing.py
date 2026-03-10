"""
her-ai-briefing Lambda — Phase E
Triggered: EventBridge cron every day at 6:55 AM IST (1:25 AM UTC)
           cron(25 1 * * ? *)
Memory: 128 MB | Timeout: 60s
Purpose: Pre-generate Sudeep's morning briefing BEFORE he wakes up
         Cache in Firestore briefings/today so Home screen loads INSTANTLY
         No more 10-15 second wait on first open
"""
import json, os, datetime, requests
from firebase_admin import credentials, firestore, initialize_app
import firebase_admin

GROQ_API_KEY = os.environ.get('GROQ_API_KEY', '')
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
SERPER_API_KEY = os.environ.get('SERPER_API_KEY', '')

ACTIVE_USERS = ['user1']

# Days when Sudeep has Corporate Kurukshetra video
KURUKSHETRA_DAYS = ['Monday', 'Wednesday', 'Friday']


# ─── FIREBASE INIT ───────────────────────────────────────────────────────────
def init_firebase():
    if not firebase_admin._apps:
        service_account = json.loads(os.environ.get('FIREBASE_SERVICE_ACCOUNT', '{}'))
        cred = credentials.Certificate(service_account)
        initialize_app(cred)


# ─── GROQ ────────────────────────────────────────────────────────────────────
def ask_groq(messages, max_tokens=600):
    try:
        response = requests.post(
            GROQ_URL,
            headers={'Authorization': f'Bearer {GROQ_API_KEY}', 'Content-Type': 'application/json'},
            json={'model': 'llama-3.3-70b-versatile', 'messages': messages, 'max_tokens': max_tokens},
            timeout=25,
        )
        data = response.json()
        return data['choices'][0]['message']['content'].strip()
    except Exception as e:
        print(f'Groq error: {e}')
        return ''


# ─── WEB SEARCH ──────────────────────────────────────────────────────────────
def web_search(query, num=2):
    if not SERPER_API_KEY:
        return ''
    try:
        r = requests.post(
            'https://google.serper.dev/search',
            headers={'X-API-KEY': SERPER_API_KEY, 'Content-Type': 'application/json'},
            json={'q': query, 'num': num, 'gl': 'in', 'hl': 'en'},
            timeout=8,
        )
        if r.status_code == 200:
            data = r.json()
            snippets = [
                f"- {res.get('title','')}: {res.get('snippet','')}"
                for res in data.get('organic', [])[:num]
            ]
            return '\n'.join(snippets)
    except Exception as e:
        print(f'Search error: {e}')
    return ''


# ─── DATA FETCHERS ───────────────────────────────────────────────────────────
def get_user_profile(db, user_id):
    try:
        doc = db.document(f'users/{user_id}/profile/main').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}

def get_habit_streaks(db, user_id):
    try:
        doc = db.document(f'users/{user_id}/habits/streaks').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}

def get_todays_plan(db, user_id, today_str):
    try:
        doc = db.document(f'users/{user_id}/dailyPlans/{today_str}').get()
        if doc.exists:
            p = doc.to_dict()
            if p.get('date', today_str) == today_str:
                return p
        return {}
    except:
        return {}

def get_latest_reflection(db, user_id):
    try:
        doc = db.document(f'users/{user_id}/briefings/latest_reflection').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}

def get_pending_tasks(db, user_id):
    """Get tasks from previous day that weren't completed"""
    yesterday = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
    try:
        doc = db.document(f'users/{user_id}/dailyPlans/{yesterday}').get()
        if not doc.exists:
            return []
        plan = doc.to_dict()
        completed = set(plan.get('completed_tasks', []))
        all_slots = (
            list(plan.get('morning', []) or []) +
            list(plan.get('afternoon', []) or []) +
            list(plan.get('evening', []) or [])
        )
        pending = [s.get('task', '') for s in all_slots
                   if s.get('task') and s.get('task') not in completed]
        return pending[:5]
    except:
        return []

def log_agent_action(db, user_id, action, result_summary):
    try:
        db.collection(f'users/{user_id}/agent_logs').add({
            'agent': 'briefing_agent',
            'action': action,
            'result_summary': result_summary[:200] if result_summary else '',
            'status': 'completed',
            'timestamp': firestore.SERVER_TIMESTAMP,
            'date': datetime.date.today().isoformat(),
        })
    except Exception as e:
        print(f'Log error: {e}')


# ─── PLAN GENERATOR (if no plan exists yet) ──────────────────────────────────
def generate_todays_plan(db, user_id, today, day_name, is_weekend):
    """Generate today's plan if it hasn't been created yet"""
    schedule_note = ""
    if not is_weekend:
        schedule_note = "Sudeep has corporate job today. Leaves 7:10am, returns 7:15pm. Plan around this."
        if day_name in KURUKSHETRA_DAYS:
            schedule_note += " Corporate Kurukshetra video at 7:30pm."
    else:
        schedule_note = f"It's {day_name} — no corporate job. Full creative day."
        if day_name == 'Sunday':
            schedule_note += " Sunday debate video due for Phokat ka Gyan."

    prompt = f"""Create Sudeep's daily plan for {day_name}, {today.strftime('%B %d %Y')}.

{schedule_note}

HABITS: Daily short at 8:30am (Phokat ka Gyan), 30-60min sketch, 30min ukulele, 30min exercise.

Return ONLY valid JSON:
{{
  "morning":   [{{"time": "H:MM AM", "task": "task", "duration": "X min", "domain": "domain"}}],
  "afternoon": [{{"time": "H:MM PM", "task": "task", "duration": "X min", "domain": "domain"}}],
  "evening":   [{{"time": "H:MM PM", "task": "task", "duration": "X min", "domain": "domain"}}],
  "top_priority": "most important task today",
  "motivation": "one energising line"
}}"""

    try:
        raw = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=700)
        clean = raw.strip().replace('```json', '').replace('```', '').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}') + 1]
        plan = json.loads(clean)
        plan['date'] = today.isoformat()
        plan['day'] = day_name
        plan.setdefault('completed_tasks', [])
        # Save to Firestore
        db.document(f'users/{user_id}/dailyPlans/{today.isoformat()}').set({
            **plan,
            'generated_at': firestore.SERVER_TIMESTAMP,
            'generated_by': 'her-ai-briefing',
        })
        print(f"Pre-generated plan for {today.isoformat()}")
        return plan
    except Exception as e:
        print(f'Plan generation error: {e}')
        return {}


# ─── CORE BRIEFING LOGIC ─────────────────────────────────────────────────────
def run_morning_briefing(db, user_id):
    today = datetime.date.today()
    today_str = today.isoformat()
    day_name = today.strftime('%A')
    is_weekend = today.weekday() >= 5

    print(f"Generating briefing for {user_id} | {today_str} ({day_name})")

    # Check if briefing already cached for today
    try:
        existing = db.document(f'users/{user_id}/briefings/today').get()
        if existing.exists:
            cached = existing.to_dict()
            if cached.get('date') == today_str:
                print(f"Briefing already cached for {today_str} — skipping")
                return cached
    except:
        pass

    # Gather data
    profile = get_user_profile(db, user_id)
    streaks = get_habit_streaks(db, user_id)
    plan = get_todays_plan(db, user_id, today_str)
    pending_yesterday = get_pending_tasks(db, user_id)
    latest_reflection = get_latest_reflection(db, user_id)

    # If no plan exists, generate one now
    if not plan or not (plan.get('morning') or plan.get('afternoon') or plan.get('evening')):
        print("No plan for today — generating one now...")
        plan = generate_todays_plan(db, user_id, today, day_name, is_weekend)

    # Build schedule summary from plan
    all_slots = (
        list(plan.get('morning', []) or []) +
        list(plan.get('afternoon', []) or []) +
        list(plan.get('evening', []) or [])
    )
    schedule_lines = [
        f"  {s.get('time', '')} — {s.get('task', '')}"
        for s in all_slots if s.get('time') and s.get('task')
    ]
    schedule_summary = '\n'.join(schedule_lines[:8])
    top_priority = plan.get('top_priority', 'Phokat ka Gyan daily short')

    # Habit streak summary
    streak_lines = []
    for habit, data in streaks.items():
        if isinstance(data, dict):
            streak = data.get('current_streak', 0)
            if streak > 0:
                streak_lines.append(f"  {habit}: {streak}🔥")
    streak_summary = '\n'.join(streak_lines) if streak_lines else '  No active streaks yet'

    # Quick news search relevant to Sudeep's domains
    news_context = ''
    try:
        results = web_search('YouTube monetisation creators India 2024 OR content creator news India', 2)
        if results:
            news_context = f"\nRELEVANT NEWS:\n{results}"
    except:
        pass

    # Previous week's focus from reflection
    next_week_focus = latest_reflection.get('next_week_focus', '')
    monday_kickoff = latest_reflection.get('monday_kickoff', '')

    # Build briefing with Groq
    pending_str = (', '.join(pending_yesterday[:3])) if pending_yesterday else 'None — clean slate!'
    special_note = ''
    if day_name == 'Monday' and monday_kickoff:
        special_note = f"\nMONDAY KICKOFF MESSAGE: {monday_kickoff}"
    if day_name in KURUKSHETRA_DAYS and not is_weekend:
        special_note += "\nREMINDER: Corporate Kurukshetra video tonight at 7:30 PM"

    prompt = f"""You are Samantha — Sudeep's personal AI. Generate his morning briefing for {day_name}, {today.strftime('%B %d')}.

TODAY'S SCHEDULE:
{schedule_summary if schedule_summary else 'Plan not set yet'}

TOP PRIORITY: {top_priority}

HABIT STREAKS:
{streak_summary}

PENDING FROM YESTERDAY: {pending_str}

WEEKLY FOCUS: {next_week_focus if next_week_focus else 'Stay consistent across all 7 domains'}
{special_note}
{news_context}

Write a brief, energising morning briefing. 3-4 sentences max. Be specific to his data.
Mention today's top priority. Reference a streak if it's impressive (5+ days).
If it's Monday, be extra motivating about the week ahead.
Sound like a sharp best friend, not a corporate assistant.

Return ONLY valid JSON:
{{
  "greeting": "Good morning Sudeep! [1-2 sentence personalised opening]",
  "top_priority_message": "Today's #1: [specific task with why it matters]",
  "habit_nudge": "Habit reminder — [specific streak or encouragement]",
  "news_snippet": "[brief relevant news if available, else empty string]",
  "full_briefing": "Complete 3-4 sentence morning message combining all the above naturally"
}}"""

    try:
        raw = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=500)
        clean = raw.strip().replace('```json', '').replace('```', '').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}') + 1]
        briefing = json.loads(clean)
    except Exception as e:
        print(f'Briefing parse error: {e}')
        briefing = {
            'greeting': f"Good morning Sudeep! Happy {day_name}.",
            'top_priority_message': f"Today's #1: {top_priority}",
            'habit_nudge': "Keep those habits alive — every day compounds.",
            'news_snippet': '',
            'full_briefing': f"Good morning Sudeep! Today's priority is {top_priority}. Keep your habits going — every consistent day compounds toward your goals.",
        }

    # Cache in Firestore briefings/today for instant Home screen load
    cache_doc = {
        **briefing,
        'date': today_str,
        'day': day_name,
        'is_weekend': is_weekend,
        'top_priority': top_priority,
        'schedule_slots': all_slots[:8],
        'habit_streaks': {k: (v.get('current_streak', 0) if isinstance(v, dict) else 0)
                          for k, v in streaks.items()},
        'pending_yesterday': pending_yesterday,
        'generated_at': firestore.SERVER_TIMESTAMP,
        'generated_by': 'her-ai-briefing',
    }

    try:
        db.document(f'users/{user_id}/briefings/today').set(cache_doc)
        print(f"Briefing cached for {user_id} on {today_str}")
    except Exception as e:
        print(f'Cache error: {e}')

    log_agent_action(db, user_id, 'morning_briefing_auto',
                     briefing.get('full_briefing', '')[:100])
    return cache_doc


# ── Push notification helper ─────────────────────────────────────────────────
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


# ─── LAMBDA HANDLER ──────────────────────────────────────────────────────────
def lambda_handler(event, context):
    """
    Called by EventBridge every day at 6:55 AM IST
    Also callable manually: { "user_id": "user1" }
    """
    print(f"her-ai-briefing invoked | event: {json.dumps(event)[:200]}")
    init_firebase()
    db = firestore.client()

    manual_user = event.get('user_id') if isinstance(event, dict) else None
    users = [manual_user] if manual_user else ACTIVE_USERS

    results = {}
    for user_id in users:
        try:
            briefing = run_morning_briefing(db, user_id)
            top_priority = briefing.get('top_priority', '')
            greeting     = briefing.get('greeting', 'Good morning!')
            # Send push notification to wake up the user
            _send_push(db, user_id,
                title='🌅 Good morning, Sudeep!',
                body=f"{greeting[:80]}" if greeting else f"Your top priority: {top_priority[:60]}",
                data={'tab': 'home', 'type': 'morning_briefing'}
            )
            results[user_id] = {
                'status': 'ok',
                'date': datetime.date.today().isoformat(),
                'top_priority': top_priority,
            }
        except Exception as e:
            print(f"Error for {user_id}: {e}")
            results[user_id] = {'status': 'error', 'error': str(e)}

    print(f"Briefing complete: {results}")
    return {'statusCode': 200, 'body': json.dumps(results)}
