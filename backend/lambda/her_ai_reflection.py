"""
her-ai-reflection Lambda — Phase D
Triggered: EventBridge cron every Sunday 9:00 PM IST (3:30 PM UTC)
           cron(30 15 ? * SUN *)
Memory: 128 MB | Timeout: 60s
Purpose: Auto-generate weekly reflection for all active users
         Save to Firestore weekly_reflections/
         Cache summary in Firestore briefings/latest_reflection for Home screen
"""
import json, os, datetime, requests
from firebase_admin import credentials, firestore, initialize_app
import firebase_admin

GROQ_API_KEY = os.environ.get('GROQ_API_KEY', '')
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

# Active users to run reflection for
ACTIVE_USERS = ['user1']


# ─── FIREBASE INIT ───────────────────────────────────────────────────────────
def init_firebase():
    if not firebase_admin._apps:
        service_account = json.loads(os.environ.get('FIREBASE_SERVICE_ACCOUNT', '{}'))
        cred = credentials.Certificate(service_account)
        initialize_app(cred)


# ─── GROQ ────────────────────────────────────────────────────────────────────
def ask_groq(messages, max_tokens=800):
    try:
        response = requests.post(
            GROQ_URL,
            headers={'Authorization': f'Bearer {GROQ_API_KEY}', 'Content-Type': 'application/json'},
            json={'model': 'llama-3.3-70b-versatile', 'messages': messages, 'max_tokens': max_tokens},
            timeout=30,
        )
        data = response.json()
        return data['choices'][0]['message']['content'].strip()
    except Exception as e:
        print(f'Groq error: {e}')
        return ''


# ─── DATA FETCHERS ───────────────────────────────────────────────────────────
def get_user_profile(db, user_id):
    try:
        doc = db.document(f'users/{user_id}/profile/main').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}

def get_week_conversations(db, user_id):
    try:
        week_ago = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
        docs = (db.collection(f'users/{user_id}/conversations')
                .where('date', '>=', week_ago)
                .limit(60).stream())
        return [d.to_dict() for d in docs]
    except:
        return []

def get_week_plans(db, user_id):
    """Get daily plans for the past 7 days"""
    plans = []
    today = datetime.date.today()
    for i in range(7):
        day = today - datetime.timedelta(days=i)
        try:
            doc = db.document(f'users/{user_id}/dailyPlans/{day.isoformat()}').get()
            if doc.exists:
                p = doc.to_dict()
                p['_date'] = day.isoformat()
                plans.append(p)
        except:
            pass
    return plans

def get_habit_streaks(db, user_id):
    try:
        doc = db.document(f'users/{user_id}/habits/streaks').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}

def get_week_mood_logs(db, user_id):
    try:
        week_ago = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
        docs = (db.collection(f'users/{user_id}/dailyLogs')
                .where('date', '>=', week_ago)
                .limit(7).stream())
        return [d.to_dict() for d in docs]
    except:
        return []


# ─── INTERACTION LOG ─────────────────────────────────────────────────────────
def log_agent_action(db, user_id, action, result_summary):
    try:
        db.collection(f'users/{user_id}/agent_logs').add({
            'agent': 'reflection_agent',
            'action': action,
            'result_summary': result_summary[:200] if result_summary else '',
            'status': 'completed',
            'timestamp': firestore.SERVER_TIMESTAMP,
            'date': datetime.date.today().isoformat(),
        })
    except Exception as e:
        print(f'Log error: {e}')


# ─── CORE REFLECTION LOGIC ───────────────────────────────────────────────────
def run_weekly_reflection(db, user_id):
    print(f"Running weekly reflection for {user_id}...")
    today = datetime.date.today()
    week_of = today.isoformat()

    # Check if reflection already ran this week (avoid double-run)
    try:
        existing = (db.collection(f'users/{user_id}/weekly_reflections')
                    .where('week_of', '==', week_of)
                    .limit(1).stream())
        if list(existing):
            print(f"Reflection already exists for {week_of} — skipping")
            return None
    except:
        pass

    # Gather all data
    profile = get_user_profile(db, user_id)
    conversations = get_week_conversations(db, user_id)
    plans = get_week_plans(db, user_id)
    streaks = get_habit_streaks(db, user_id)
    mood_logs = get_week_mood_logs(db, user_id)

    # Summarise conversations
    conv_lines = []
    for c in conversations[-25:]:
        msg = c.get('userMessage', '')[:80]
        date = c.get('date', '')
        if msg:
            conv_lines.append(f"  [{date}] {msg}")
    conv_summary = '\n'.join(conv_lines) if conv_lines else 'No conversations this week'

    # Summarise plans — count completed tasks
    total_tasks = 0
    completed_tasks = 0
    plan_lines = []
    for plan in plans:
        day = plan.get('_date', '')
        done = plan.get('completed_tasks', [])
        morning = plan.get('morning', []) or []
        afternoon = plan.get('afternoon', []) or []
        evening = plan.get('evening', []) or []
        all_slots = morning + afternoon + evening
        day_total = len(all_slots)
        day_done = len(done)
        total_tasks += day_total
        completed_tasks += day_done
        if day_total > 0:
            plan_lines.append(f"  {day}: {day_done}/{day_total} tasks done")
    plan_summary = '\n'.join(plan_lines) if plan_lines else 'No plans recorded this week'
    completion_rate = round(completed_tasks / total_tasks, 2) if total_tasks > 0 else 0.0

    # Habit streaks summary
    habit_lines = []
    for habit, data in streaks.items():
        if isinstance(data, dict):
            streak = data.get('current_streak', 0)
            habit_lines.append(f"  {habit}: {streak} day streak")
    habit_summary = '\n'.join(habit_lines) if habit_lines else 'No habit data'

    # Mood distribution
    mood_counts = {}
    for log in mood_logs:
        mood = log.get('mood', 'neutral')
        mood_counts[mood] = mood_counts.get(mood, 0) + 1
    mood_trend = max(mood_counts, key=mood_counts.get) if mood_counts else 'neutral'

    # Build Groq prompt
    prompt = f"""You are Samantha — Sudeep's personal AI companion. You've watched over his week.
Today is Sunday {week_of}. Generate a deeply personal weekly reflection for Sudeep.

━━━ SUDEEP'S LIFE CONTEXT ━━━
- 7 domains: Phokat ka Gyan (YouTube/Instagram, monetisation is #1 goal), 
  Traveler Tree (travel app), Gita Learning App, Sapna Canvas (wife's art brand),
  Pencil Sketch, Ukulele, Health
- Corporate job Mon-Fri, 9-6pm
- 1-year goal: Phokat ka Gyan monetised, Traveler Tree MVP live
- 3-year goal: Own company, quit corporate job

━━━ THIS WEEK'S DATA ━━━
CONVERSATIONS ({len(conversations)} total):
{conv_summary}

DAILY PLAN COMPLETION:
{plan_summary}
Overall: {completed_tasks}/{total_tasks} tasks ({int(completion_rate*100)}%)

HABIT STREAKS:
{habit_summary}

MOOD TREND: {mood_trend}

━━━ GENERATE REFLECTION ━━━
Be warm, personal, honest — like a best friend who watched your whole week.
Don't be generic. Reference specific things from the data.
If he didn't do much, be honest but kind. If he crushed it, celebrate it.

Return ONLY valid JSON:
{{
  "week_summary": "2-3 honest sentences about how the week really went",
  "wins": ["specific win 1", "specific win 2", "specific win 3"],
  "missed_opportunities": ["what genuinely could have been better"],
  "habit_completion_rate": "{int(completion_rate*100)}%",
  "task_completion": "{completed_tasks}/{total_tasks}",
  "dominant_mood": "{mood_trend}",
  "top_domain": "which life domain got most focus",
  "neglected_domain": "which domain got least attention — honest call",
  "insights": [
    "deep personal observation about his patterns this week",
    "something specific he should know about himself"
  ],
  "next_week_focus": "single most important thing for next week — be specific",
  "monday_kickoff": "One energising message for Monday morning — personal, not generic",
  "samanthas_message": "Warm 2-3 sentence personal message from Samantha to Sudeep about his week"
}}"""

    try:
        raw = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=900)
        clean = raw.strip().replace('```json', '').replace('```', '').strip()
        if '{' in clean:
            clean = clean[clean.index('{'):clean.rindex('}') + 1]
        reflection = json.loads(clean)
    except Exception as e:
        print(f'Groq reflection parse error: {e}')
        reflection = {
            'week_summary': 'Weekly reflection could not be generated this week.',
            'wins': [], 'missed_opportunities': [],
            'habit_completion_rate': f'{int(completion_rate*100)}%',
            'task_completion': f'{completed_tasks}/{total_tasks}',
            'dominant_mood': mood_trend,
            'top_domain': 'unknown', 'neglected_domain': 'unknown',
            'insights': [], 'next_week_focus': 'Stay consistent',
            'monday_kickoff': 'New week, new opportunities. Go get it Sudeep.',
            'samanthas_message': 'Every week you show up. That\'s what matters.',
        }

    # Save full reflection to Firestore
    try:
        db.collection(f'users/{user_id}/weekly_reflections').add({
            **reflection,
            'week_of': week_of,
            'completion_rate': completion_rate,
            'total_tasks': total_tasks,
            'completed_tasks': completed_tasks,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'generated_by': 'her-ai-reflection',
        })
        print(f"Saved reflection for {user_id} week_of={week_of}")
    except Exception as e:
        print(f'Firestore save error: {e}')

    # Cache condensed version in briefings/latest_reflection for Home screen instant load
    try:
        db.document(f'users/{user_id}/briefings/latest_reflection').set({
            'week_of': week_of,
            'samanthas_message': reflection.get('samanthas_message', ''),
            'next_week_focus': reflection.get('next_week_focus', ''),
            'monday_kickoff': reflection.get('monday_kickoff', ''),
            'wins': reflection.get('wins', [])[:3],
            'habit_completion_rate': reflection.get('habit_completion_rate', ''),
            'task_completion': reflection.get('task_completion', ''),
            'top_domain': reflection.get('top_domain', ''),
            'neglected_domain': reflection.get('neglected_domain', ''),
            'timestamp': firestore.SERVER_TIMESTAMP,
        })
        print(f"Cached reflection summary in briefings/latest_reflection")
    except Exception as e:
        print(f'Cache save error: {e}')

    log_agent_action(db, user_id, 'weekly_reflection_auto', reflection.get('week_summary', '')[:100])
    return reflection


# ─── LAMBDA HANDLER ──────────────────────────────────────────────────────────
def lambda_handler(event, context):
    """
    Called by EventBridge every Sunday 9pm IST
    event may contain: { "user_id": "user1" } for manual trigger
    or be empty (EventBridge scheduled)
    """
    print(f"her-ai-reflection invoked | event: {json.dumps(event)[:200]}")
    init_firebase()
    db = firestore.client()

    # Support manual trigger with specific user, or run all active users
    manual_user = event.get('user_id') if isinstance(event, dict) else None
    users = [manual_user] if manual_user else ACTIVE_USERS

    results = {}
    for user_id in users:
        try:
            reflection = run_weekly_reflection(db, user_id)
            results[user_id] = {
                'status': 'ok' if reflection else 'skipped',
                'week_of': datetime.date.today().isoformat(),
            }
        except Exception as e:
            print(f"Error for {user_id}: {e}")
            results[user_id] = {'status': 'error', 'error': str(e)}

    print(f"Reflection complete: {results}")
    return {'statusCode': 200, 'body': json.dumps(results)}
