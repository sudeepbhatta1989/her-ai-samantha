"""
her-ai-notifier Lambda
Runs every 15 minutes via EventBridge: cron(0/15 * * * ? *)
Checks today's plan and sends push notification for tasks starting in ~15 minutes
Only notifies tasks NOT already in completed_tasks
"""

import json
import os
import datetime
import firebase_admin
from firebase_admin import credentials, firestore, messaging

# ── Init Firebase ──
if not firebase_admin._apps:
    sa = json.loads(os.environ['FIREBASE_SERVICE_ACCOUNT'])
    cred = credentials.Certificate(sa)
    firebase_admin.initialize_app(cred)

USER_ID = 'user1'
IST_OFFSET = datetime.timezone(datetime.timedelta(hours=5, minutes=30))

# Task emojis for nicer notifications
TASK_EMOJIS = {
    'exercise': '🏃',
    'ukulele': '🎵',
    'sketch': '✏️',
    'pencil sketch': '✏️',
    'daily short': '🎬',
    'phokat': '🎬',
    'breakfast': '🍳',
    'lunch': '🥗',
    'work': '💼',
    'corporate kurukshetra': '🎥',
    'free time': '☕',
    'get ready': '👔',
    'freshen up': '🚿',
    'leave': '🚗',
    'return': '🏠',
    'meditation': '🧘',
    'reading': '📚',
    'meeting': '📅',
}


def get_task_emoji(task_name):
    task_lower = task_name.lower()
    for keyword, emoji in TASK_EMOJIS.items():
        if keyword in task_lower:
            return emoji
    return '⏰'


def parse_time_to_minutes(time_str):
    """
    Parse '6:30 AM' or '7:15 PM' to minutes since midnight (IST).
    Returns int or None on failure.
    """
    try:
        time_str = time_str.strip().upper()
        if ':' in time_str:
            parts = time_str.replace('AM', '').replace('PM', '').strip().split(':')
            hour = int(parts[0])
            minute = int(parts[1])
        else:
            parts = time_str.replace('AM', '').replace('PM', '').strip()
            hour = int(parts)
            minute = 0

        if 'PM' in time_str and hour != 12:
            hour += 12
        elif 'AM' in time_str and hour == 12:
            hour = 0

        return hour * 60 + minute
    except:
        return None


def send_push(db, title, body, data=None):
    """Send FCM push notification"""
    try:
        user_doc = db.document(f'users/{USER_ID}').get()
        if not user_doc.exists:
            print("User doc not found")
            return False
        fcm_token = user_doc.to_dict().get('fcm_token', '')
        if not fcm_token:
            print("No FCM token")
            return False

        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound='default', badge=1)
                )
            ),
            token=fcm_token,
        )
        response = messaging.send(msg)
        print(f"Push sent: {response}")
        return True
    except Exception as e:
        print(f"Push error: {e}")
        return False


def lambda_handler(event, context):
    """Main entry — runs every 15 minutes"""
    db = firestore.client()

    # Current IST time in minutes since midnight
    now_ist = datetime.datetime.now(IST_OFFSET)
    current_minutes = now_ist.hour * 60 + now_ist.minute
    today_str = now_ist.date().isoformat()

    print(f"Notifier running at {now_ist.strftime('%H:%M IST')} ({current_minutes} min)")

    # Load today's plan
    plan_ref = db.document(f'users/{USER_ID}/dailyPlans/{today_str}')
    plan_doc = plan_ref.get()

    if not plan_doc.exists:
        print(f"No plan found for {today_str}")
        return {'status': 'no_plan', 'date': today_str}

    plan = plan_doc.to_dict()
    completed_tasks = [t.lower() for t in plan.get('completed_tasks', [])]

    # Collect all tasks across morning/afternoon/evening
    all_tasks = []
    for section in ['morning', 'afternoon', 'evening']:
        for slot in plan.get(section, []):
            task_name = slot.get('task', '').strip()
            time_str = slot.get('time', '').strip()
            if task_name and time_str:
                task_minutes = parse_time_to_minutes(time_str)
                if task_minutes is not None:
                    all_tasks.append({
                        'task': task_name,
                        'time': time_str,
                        'minutes': task_minutes,
                    })

    # Find tasks starting in 14-16 minute window (±1 min tolerance for Lambda timing)
    NOTIFY_WINDOW_MIN = 13
    NOTIFY_WINDOW_MAX = 17
    notifications_sent = []

    for task in all_tasks:
        minutes_until = task['minutes'] - current_minutes

        if NOTIFY_WINDOW_MIN <= minutes_until <= NOTIFY_WINDOW_MAX:
            # Check not already completed
            if task['task'].lower() not in completed_tasks:
                emoji = get_task_emoji(task['task'])
                title = f"{emoji} Starting in 15 min"
                body = f"{task['task']} — {task['time']}"

                sent = send_push(db, title, body, data={
                    'action': 'task_reminder',
                    'task': task['task'],
                    'time': task['time'],
                })

                if sent:
                    notifications_sent.append(task['task'])
                    print(f"Notified: {task['task']} at {task['time']}")

    # Special: notify if no tasks were found and it's morning (gentle nudge)
    if not notifications_sent and 6 * 60 <= current_minutes <= 6 * 60 + 16:
        total_tasks = len(all_tasks)
        done_count = len([t for t in all_tasks if t['task'].lower() in completed_tasks])
        if done_count == 0 and total_tasks > 0:
            send_push(db,
                title="🌅 Good morning, Sudeep!",
                body=f"Your day has {total_tasks} tasks planned. First up: {all_tasks[0]['task']} at {all_tasks[0]['time']}",
                data={'action': 'open_plan'}
            )

    return {
        'status': 'ok',
        'time_ist': now_ist.strftime('%H:%M'),
        'tasks_checked': len(all_tasks),
        'notifications_sent': notifications_sent,
    }
