"""
her-ai-content Lambda
Runs daily at 7:00 PM IST (13:30 UTC) via EventBridge
Generates tomorrow's Phokat ka Gyan short script automatically
Saves to Firestore: users/{userId}/content_scripts/{date}
Sends push notification: "📝 Tomorrow's script is ready"
"""

import json
import os
import datetime
import requests
import firebase_admin
from firebase_admin import credentials, firestore, messaging

# ── Init Firebase ──
if not firebase_admin._apps:
    sa = json.loads(os.environ['FIREBASE_SERVICE_ACCOUNT'])
    cred = credentials.Certificate(sa)
    firebase_admin.initialize_app(cred)

GROQ_API_KEY = os.environ.get('GROQ_API_KEY', '')
USER_ID = 'user1'

# Topics to avoid repeating — pulled from recent scripts
AWARENESS_TOPICS = [
    "water pollution in Indian rivers",
    "mental health stigma in India",
    "road safety and helmet laws",
    "food adulteration and FSSAI",
    "digital literacy in rural India",
    "soil degradation and farming crisis",
    "noise pollution in cities",
    "single-use plastic reality",
    "air quality index and health",
    "voting rights and civic duty",
    "child labour in urban India",
    "online scam awareness",
    "period poverty in India",
    "organ donation myths",
    "e-waste management",
    "rainwater harvesting at home",
    "fast fashion environmental impact",
    "drug addiction in youth",
    "public transport vs private cars",
    "RTI — Right to Information power",
]


def ask_groq(messages, max_tokens=2000):
    resp = requests.post(
        'https://api.openai.com/v1/chat/completions'
        if 'openai' in GROQ_API_KEY else
        'https://api.groq.com/openai/v1/chat/completions',
        headers={
            'Authorization': f'Bearer {GROQ_API_KEY}',
            'Content-Type': 'application/json',
        },
        json={
            'model': 'llama-3.3-70b-versatile',
            'messages': messages,
            'max_tokens': max_tokens,
            'temperature': 0.8,
        },
        timeout=45
    )
    resp.raise_for_status()
    return resp.json()['choices'][0]['message']['content']


def get_recent_script_topics(db):
    """Get last 10 script topics to avoid repetition"""
    try:
        docs = db.collection(f'users/{USER_ID}/content_scripts') \
            .order_by('created_at', direction='DESCENDING') \
            .limit(10).stream()
        return [d.to_dict().get('topic', '') for d in docs]
    except:
        return []


def pick_fresh_topic(db):
    """Pick a topic not covered recently"""
    recent = get_recent_script_topics(db)
    recent_lower = [r.lower() for r in recent]

    for topic in AWARENESS_TOPICS:
        if not any(t in topic.lower() for t in recent_lower):
            return topic

    # All covered — ask Groq to suggest a fresh one
    prompt = f"""Suggest ONE fresh, specific awareness topic for a 60-90 second Hindi/Hinglish YouTube short in India.
Recent topics already covered: {', '.join(recent[:5])}
Return ONLY the topic phrase (5-10 words). No explanation."""
    return ask_groq([{'role': 'user', 'content': prompt}], max_tokens=50).strip()


def generate_script(topic):
    """Generate a full Phokat ka Gyan short script"""
    tomorrow = datetime.date.today() + datetime.timedelta(days=1)
    day_name = tomorrow.strftime('%A')

    prompt = f"""You are writing a script for "Phokat ka Gyan" — Sudeep's YouTube/Instagram daily awareness shorts channel.

TOPIC: {topic}
FOR: {day_name}, {tomorrow.strftime('%B %d')}

CHANNEL STYLE:
- Hindi/Hinglish mix (mostly Hindi, English technical terms OK)
- Direct, punchy, conversational — like talking to a close friend
- Awareness focused — make the viewer think and share
- Hook in FIRST 3 SECONDS — must stop the scroll immediately
- 60-90 seconds total when spoken at normal pace
- Always ends with a thought-provoking question

Write the complete shooting script:

🎣 HOOK (0-5 sec) — One powerful opening line + what to show on screen

📢 MAIN CONTENT (5-75 sec) — 3-4 key points with facts
Point 1:
Point 2:
Point 3:
[Point 4 if needed:]

💡 INSIGHT (75-85 sec) — The "why should I care" moment

🔥 CTA (85-90 sec) — Closing question to drive comments

---
📱 ON-SCREEN TEXT OVERLAYS (3 key phrases to flash):
🎵 BACKGROUND MUSIC MOOD:
⏱️ ESTIMATED DURATION:
🎯 THUMBNAIL IDEA:"""

    return ask_groq([{'role': 'user', 'content': prompt}], max_tokens=2000)


def send_push(db, title, body, data=None):
    """Send push notification via FCM"""
    try:
        user_doc = db.document(f'users/{USER_ID}').get()
        if not user_doc.exists:
            return
        fcm_token = user_doc.to_dict().get('fcm_token', '')
        if not fcm_token:
            print("No FCM token found")
            return

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
    except Exception as e:
        print(f"Push error: {e}")


def lambda_handler(event, context):
    """Main entry — runs at 7 PM IST daily"""
    db = firestore.client()
    tomorrow = datetime.date.today() + datetime.timedelta(days=1)
    script_date = tomorrow.isoformat()
    day_name = tomorrow.strftime('%A')

    print(f"Generating script for {script_date} ({day_name})")

    # Check if script already exists for tomorrow
    script_ref = db.document(f'users/{USER_ID}/content_scripts/{script_date}_phokat_short')
    existing = script_ref.get()
    if existing.exists:
        print(f"Script already exists for {script_date} — skipping")
        return {'status': 'skipped', 'reason': 'already_exists', 'date': script_date}

    # Pick topic and generate script
    topic = pick_fresh_topic(db)
    print(f"Topic selected: {topic}")

    script = generate_script(topic)
    print(f"Script generated ({len(script)} chars)")

    # Save to Firestore
    script_ref.set({
        'type': 'phokat_short',
        'topic': topic,
        'script': script,
        'title': topic,
        'date': script_date,
        'day': day_name,
        'created_at': firestore.SERVER_TIMESTAMP,
        'source': 'auto_generated',
        'reviewed': False,
    })
    print(f"Script saved to Firestore")

    # Send push notification
    send_push(
        db,
        title="📝 Tomorrow's script is ready!",
        body=f"Phokat ka Gyan: {topic[:50]} — Tap to review and edit with Samantha",
        data={
            'action': 'open_content',
            'script_date': script_date,
            'content_type': 'phokat_short',
        }
    )

    return {
        'status': 'ok',
        'date': script_date,
        'topic': topic,
        'script_length': len(script),
    }
