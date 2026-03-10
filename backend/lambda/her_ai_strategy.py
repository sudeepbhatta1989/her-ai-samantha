"""
her-ai-strategy Lambda
Runs on 1st of every month at 8:00 AM IST (02:30 UTC) via EventBridge
Analyzes all 7 domains over past 30 days and generates:
  1. Domain-by-domain scorecard + action items
  2. Weekly focus calendar for the month
  3. Gap analysis: where time went vs where it should go
Saves to Firestore: users/{userId}/strategy_reports/{YYYY-MM}
Sends push notification with summary
"""

import json
import os
import datetime
import requests
import firebase_admin
from firebase_admin import credentials, firestore, messaging

if not firebase_admin._apps:
    sa = json.loads(os.environ['FIREBASE_SERVICE_ACCOUNT'])
    cred = credentials.Certificate(sa)
    firebase_admin.initialize_app(cred)

GROQ_API_KEY = os.environ.get('GROQ_API_KEY', '')
USER_ID = 'user1'

DOMAINS = [
    {'id': 'corporate',       'name': 'Corporate Job',           'goal': 'Stable income, perform well, avoid burnout'},
    {'id': 'phokat',          'name': 'Phokat ka Gyan',          'goal': '1yr: monetisation — daily shorts + Sunday debate'},
    {'id': 'traveler_tree',   'name': 'Traveler Tree',           'goal': '3yr: launch MVP travel community platform'},
    {'id': 'gita_app',        'name': 'Gita Learning App',       'goal': '3yr: build and launch app'},
    {'id': 'sapna_canvas',    'name': 'Sapna Canvas',            'goal': 'Vision board / goal visualization tool'},
    {'id': 'skills',          'name': 'Skills (Sketch+Ukulele)', 'goal': 'Daily habit — 30min sketch, 30min ukulele'},
    {'id': 'health',          'name': 'Health',                  'goal': 'Daily exercise, good sleep, no junk food'},
]

# Expected daily minutes per domain (Sudeep's ideal allocation)
IDEAL_DAILY_MINUTES = {
    'corporate':     480,  # 8hr work
    'phokat':         90,  # daily short + planning
    'traveler_tree':  30,  # 30min development
    'gita_app':       30,  # 30min development
    'sapna_canvas':   20,  # 20min
    'skills':         60,  # 30min sketch + 30min ukulele
    'health':         60,  # 30min exercise + wind-down
}


def ask_groq(messages, max_tokens=3000):
    resp = requests.post(
        'https://api.groq.com/openai/v1/chat/completions',
        headers={'Authorization': f'Bearer {GROQ_API_KEY}', 'Content-Type': 'application/json'},
        json={'model': 'llama-3.3-70b-versatile', 'messages': messages, 'max_tokens': max_tokens, 'temperature': 0.7},
        timeout=60
    )
    resp.raise_for_status()
    return resp.json()['choices'][0]['message']['content']


def get_interaction_logs(db, days=30):
    """Get all interaction logs from past N days"""
    cutoff = datetime.datetime.now() - datetime.timedelta(days=days)
    try:
        docs = db.collection(f'users/{USER_ID}/interaction_logs') \
            .order_by('timestamp', direction='DESCENDING') \
            .limit(200).stream()
        logs = []
        for d in docs:
            data = d.to_dict()
            logs.append({
                'message': data.get('userMessage', '')[:200],
                'intent': data.get('intent', ''),
                'agent': data.get('agent', ''),
            })
        return logs
    except Exception as e:
        print(f"Logs error: {e}")
        return []


def get_habit_streaks(db):
    """Get current habit streaks"""
    try:
        doc = db.document(f'users/{USER_ID}/habits/streaks').get()
        return doc.to_dict() if doc.exists else {}
    except:
        return {}


def get_weekly_reflections(db):
    """Get last 4 weekly reflections"""
    try:
        docs = db.collection(f'users/{USER_ID}/weekly_reflections') \
            .order_by('generated_at', direction='DESCENDING') \
            .limit(4).stream()
        return [d.to_dict() for d in docs]
    except:
        return []


def get_completed_plans(db, days=30):
    """Get daily plans from last N days and count completed tasks per domain"""
    completed_by_domain = {d['id']: 0 for d in DOMAINS}
    total_days_with_plans = 0

    today = datetime.date.today()
    try:
        for i in range(days):
            date = today - datetime.timedelta(days=i)
            doc = db.document(f'users/{USER_ID}/dailyPlans/{date.isoformat()}').get()
            if not doc.exists:
                continue
            total_days_with_plans += 1
            plan = doc.to_dict()
            completed = [t.lower() for t in plan.get('completed_tasks', [])]

            # Map completed tasks to domains
            for task in completed:
                if any(w in task for w in ['exercise', 'gym', 'workout', 'health']):
                    completed_by_domain['health'] += 1
                if any(w in task for w in ['sketch', 'drawing', 'pencil']):
                    completed_by_domain['skills'] += 1
                if any(w in task for w in ['ukulele', 'music', 'practice']):
                    completed_by_domain['skills'] += 1
                if any(w in task for w in ['phokat', 'daily short', 'reel', 'video', 'debate']):
                    completed_by_domain['phokat'] += 1
                if any(w in task for w in ['work', 'corporate', 'office', 'wfh']):
                    completed_by_domain['corporate'] += 1
                if any(w in task for w in ['traveler', 'travel tree', 'mvp']):
                    completed_by_domain['traveler_tree'] += 1
                if any(w in task for w in ['gita', 'app', 'flutter', 'coding']):
                    completed_by_domain['gita_app'] += 1
                if any(w in task for w in ['sapna', 'canvas', 'vision']):
                    completed_by_domain['sapna_canvas'] += 1
    except Exception as e:
        print(f"Plans error: {e}")

    return completed_by_domain, total_days_with_plans


def generate_strategy_report(db, month_label):
    """Generate the full 3-part strategy report"""
    logs = get_interaction_logs(db, days=30)
    streaks = get_habit_streaks(db)
    reflections = get_weekly_reflections(db)
    completed_by_domain, active_days = get_completed_plans(db, days=30)

    # Summarize data for the prompt
    domain_activity = []
    for d in DOMAINS:
        did = d['id']
        count = completed_by_domain.get(did, 0)
        ideal_monthly = IDEAL_DAILY_MINUTES.get(did, 30) * 30 / 60  # hours/month
        actual_pct = min(100, int((count / max(active_days, 1)) * 100))
        domain_activity.append(
            f"- {d['name']}: {count} task completions in {active_days} active days "
            f"({actual_pct}% consistency) | Goal: {d['goal']}"
        )

    streak_summary = []
    for habit, data in streaks.items():
        if isinstance(data, dict):
            streak_summary.append(f"  {habit}: {data.get('current_streak', 0)} day streak, {data.get('total_done', 0)} total done")

    reflection_summary = ""
    if reflections:
        r = reflections[0]
        reflection_summary = f"Latest reflection insight: {str(r.get('reflection', ''))[:400]}"

    chat_topics = list(set([l.get('intent', '') for l in logs if l.get('intent')]))[:10]

    today = datetime.date.today()
    month_name = today.strftime('%B %Y')
    next_month = (today.replace(day=1) + datetime.timedelta(days=32)).replace(day=1)
    next_month_name = next_month.strftime('%B %Y')

    prompt = f"""You are Samantha, Sudeep's personal AI life assistant. Generate his monthly strategy report for {next_month_name}.

━━━ SUDEEP'S LIFE CONTEXT ━━━
Corporate job: Mon-Fri, leaves 7:10 AM, returns 7:15 PM
1-year goal: Phokat ka Gyan monetisation + Traveler Tree MVP
3-year goal: Own company
10-year goal: Financial independence
7 domains: Corporate Job, Phokat ka Gyan, Traveler Tree, Gita App, Sapna Canvas, Skills, Health

━━━ LAST 30 DAYS DATA ━━━
Active days tracked: {active_days}/30

DOMAIN ACTIVITY:
{chr(10).join(domain_activity)}

HABIT STREAKS:
{chr(10).join(streak_summary) if streak_summary else "No streak data"}

CHAT INTENTS (what Sudeep asked about most):
{', '.join(chat_topics)}

{reflection_summary}

━━━ GENERATE THIS EXACT REPORT STRUCTURE ━━━

## 📊 PART 1: DOMAIN SCORECARD

For each of the 7 domains, give:
- Score: X/10 (based on consistency data above)
- Status: 🔥 On Track / ⚠️ Slipping / ❌ Neglected
- What happened: 1-2 sentences on actual activity
- Top 3 action items for {next_month_name} (specific, achievable)

## 📅 PART 2: MONTHLY FOCUS CALENDAR

Week 1 (primary focus domain + 2-3 daily actions)
Week 2 (primary focus domain + 2-3 daily actions)
Week 3 (primary focus domain + 2-3 daily actions)
Week 4 (primary focus domain + 2-3 daily actions)

Be realistic about corporate job constraints (Mon-Fri busy). Most creative work happens evenings + weekends.

## 🔍 PART 3: GAP ANALYSIS

Where time ACTUALLY went vs where it SHOULD go:
- Show as a simple table: Domain | Should | Actual | Gap
- Top 3 insights about the gaps
- One honest hard truth Sudeep needs to hear
- The single most important change for next month

End with: "📌 SAMANTHA'S VERDICT FOR {next_month_name.upper()}: [2-3 sentence direct summary of what Sudeep must focus on and why]"

Be direct, specific, and honest. No fluff. Sudeep wants real insights, not motivation quotes."""

    return ask_groq([{'role': 'user', 'content': prompt}], max_tokens=3000)


def send_push(db, title, body, data=None):
    try:
        user_doc = db.document(f'users/{USER_ID}').get()
        if not user_doc.exists:
            return
        fcm_token = user_doc.to_dict().get('fcm_token', '')
        if not fcm_token:
            return
        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound='default', badge=1))),
            token=fcm_token,
        )
        messaging.send(msg)
    except Exception as e:
        print(f"Push error: {e}")


def lambda_handler(event, context):
    db = firestore.client()
    today = datetime.date.today()
    month_label = today.strftime('%Y-%m')
    month_name = today.strftime('%B %Y')

    print(f"Generating strategy report for {month_label}")

    # Check if already generated this month
    report_ref = db.document(f'users/{USER_ID}/strategy_reports/{month_label}')
    if report_ref.get().exists:
        print("Report already exists for this month")
        return {'status': 'skipped', 'month': month_label}

    report = generate_strategy_report(db, month_label)
    print(f"Report generated ({len(report)} chars)")

    # Save to Firestore
    report_ref.set({
        'report': report,
        'month': month_label,
        'month_name': month_name,
        'generated_at': firestore.SERVER_TIMESTAMP,
        'domains_analyzed': [d['name'] for d in DOMAINS],
    })

    # Extract verdict for notification (last line roughly)
    verdict_lines = [l for l in report.split('\n') if "SAMANTHA'S VERDICT" in l or "VERDICT" in l]
    verdict_preview = verdict_lines[0][:80] if verdict_lines else "Your monthly strategy is ready"

    send_push(db,
        title=f"📊 {month_name} Strategy Report Ready",
        body=f"{verdict_preview}... Tap to review in Jarvis",
        data={'action': 'open_strategy', 'month': month_label}
    )

    return {'status': 'ok', 'month': month_label, 'report_length': len(report)}
