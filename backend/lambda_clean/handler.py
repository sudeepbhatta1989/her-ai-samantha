import json, os, requests, datetime
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
    """Detect if user wants web/internet info"""
    triggers = [
        'search', 'look up', 'find out', 'what is the latest', 'check online',
        "news", "current", "today's", "price of", 'weather', 'trending',
        'internet', 'web', 'google', 'find me', "what's happening",
        'latest news', 'recent', 'update on', 'status of', 'rate of'
    ]
    msg_lower = message.lower()
    return any(t in msg_lower for t in triggers)

# ─────────────────────────────────────────
# FIREBASE INIT
# ─────────────────────────────────────────
def init_firebase():
    if not firebase_admin._apps:
        service_account = json.loads(os.environ.get('FIREBASE_SERVICE_ACCOUNT', '{}'))
        cred = credentials.Certificate(service_account)
        initialize_app(cred)

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

def get_todays_plan(db, user_id):
    try:
        today = datetime.date.today().isoformat()
        doc = db.document(f'users/{user_id}/dailyPlans/{today}').get()
        return doc.to_dict() if doc.exists else {}
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
def save_conversation(db, user_id, user_msg, ai_reply, mood):
    """Save full conversation turn"""
    try:
        db.collection(f'users/{user_id}/conversations').add({
            'userMessage': user_msg,
            'aiReply': ai_reply,
            'mood': mood,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'date': datetime.date.today().isoformat()
        })
    except Exception as e:
        print(f"Conversation save error: {e}")

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
            'temperature': 0.6  # Lower = more direct, less rambling
        },
        timeout=30
    )
    return response.json()['choices'][0]['message']['content']

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
        for conv in recent_convs[-15:]:
            date = conv.get('date', '')
            conv_history += f"[{date}] You: {conv.get('userMessage', '')[:150]}\n"
            conv_history += f"[{date}] Samantha: {conv.get('aiReply', '')[:150]}\n"

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
        plan_text = f"\nTODAY'S PLAN:\nTop priority: {today_plan.get('top_priority', 'Not set')}\n"
        completed = today_plan.get('completed_tasks', [])
        if completed:
            plan_text += f"Completed today: {', '.join(completed)}\n"

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
1. MAX 2 SENTENCES per reply. Never 3 unless he asks for detail. Never more than 3. Ever.
2. NEVER start with praise words: "Great", "Congrats", "Amazing", "Absolutely", "Of course", "Sure", "That's awesome" — forbidden.
3. NEVER repeat what he said. If he says "I finished my sketch", don't say "Great that you finished your sketch". Just react and move on.
4. NEVER ask more than one question. Usually ask zero questions.
5. WFH/context change = immediately give a concrete revised plan. Don't ask what he wants to do. You know his life. Decide.
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

HOW YOU RESPOND — CRITICAL RULES:
BREVITY IS EVERYTHING. Most replies = 1-3 sentences max. Never more than 5 unless he explicitly asks for detail.
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

    plan_json = ask_groq([{'role': 'user', 'content': prompt}], max_tokens=800)
    clean = plan_json.strip().replace('```json', '').replace('```', '').strip()
    plan = json.loads(clean)

    today_key = today.isoformat()
    db.document(f'users/{user_id}/dailyPlans/{today_key}').set({
        **plan,
        'generated_at': firestore.SERVER_TIMESTAMP,
        'completed_tasks': [],
        'date': today_key,
        'day': day_name
    })
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
def lambda_handler(event, context):
    try:
        init_firebase()
        body = json.loads(event.get('body', '{}'))
        user_id = body.get('userId', 'user1')
        user_message = body.get('message', '')
        action = body.get('action', 'chat')

        db = firestore.client()

        # ── Generate daily plan ──
        if action == 'generate_plan':
            plan = generate_daily_plan(db, user_id)
            return _response({'plan': plan, 'status': 'ok'})

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
                convs_ref = db.collection('users').document(user_id)\
                    .collection('conversations')\
                    .order_by('timestamp', direction=firestore.Query.DESCENDING)\
                    .limit(100)
                convs = list(convs_ref.stream())
                # Group into daily sessions
                from collections import defaultdict
                daily = defaultdict(list)
                for conv in convs:
                    data = conv.to_dict()
                    ts = data.get('timestamp', '')
                    try:
                        day = ts[:10] if ts else 'unknown'
                    except:
                        day = 'unknown'
                    daily[day].append(data)
                sessions = []
                for day, msgs in sorted(daily.items(), reverse=True):
                    messages = []
                    for m in msgs:
                        if m.get('userMessage'):
                            messages.append({'role': 'user', 'content': m.get('userMessage', '')})
                        if m.get('aiReply'):
                            messages.append({'role': 'assistant', 'content': m.get('aiReply', '')})
                    if messages:
                        first_msg = msgs[0]
                        sessions.append({
                            'id': day,
                            'timestamp': first_msg.get('timestamp', day),
                            'mood': first_msg.get('mood', 'neutral'),
                            'messages': messages
                        })
                return _response({'sessions': sessions, 'status': 'ok'})
            except Exception as e:
                print(f'History error: {e}')
                return _response({'sessions': [], 'error': str(e)}, 200)

        # ── Get user profile ──
        if action == 'get_profile':
            profile = get_user_profile(db, user_id)
            return _response({'profile': profile, 'status': 'ok'})

        # ── Main chat ──
        if not user_message:
            return _response({'error': 'No message provided'}, 400)

        # Detect mood
        mood = detect_mood(user_message)

        # Gather all context
        profile = get_user_profile(db, user_id)
        recent_convs = get_recent_conversations(db, user_id, limit=20)
        important_memories = get_important_memories(db, user_id, limit=10)
        today_plan = get_todays_plan(db, user_id)
        habit_streaks = get_habit_streaks(db, user_id)
        weekly_summary = get_weekly_summary(db, user_id)

        # Build rich system prompt
        system_prompt = build_system_prompt(
            profile, recent_convs, important_memories,
            today_plan, habit_streaks, mood, weekly_summary
        )

        # Build message array with recent conversation context
        messages = [{'role': 'system', 'content': system_prompt}]

        # Add last 6 turns as actual message history for natural flow
        for conv in recent_convs[-6:]:
            messages.append({'role': 'user', 'content': conv.get('userMessage', '')})
            messages.append({'role': 'assistant', 'content': conv.get('aiReply', '')})

        # Add web search context if needed
        final_message = user_message
        if needs_web_search(user_message):
            search_results = web_search(user_message)
            if search_results:
                final_message = f"{user_message}\n\n[Web search results for context:\n{search_results}\nUse this info in your reply but keep it brief and conversational.]"

        messages.append({'role': 'user', 'content': final_message})

        # Get AI response
        ai_reply = ask_groq(messages, max_tokens=120)

        # Save everything
        save_conversation(db, user_id, user_message, ai_reply, mood)
        extract_and_save_memory(db, user_id, user_message, ai_reply, mood)
        update_daily_log(db, user_id, mood, user_message)

        return _response({
            'reply': ai_reply,
            'mood': mood,
            'status': 'ok'
        })

    except Exception as e:
        print(f"Lambda error: {str(e)}")
        import traceback
        traceback.print_exc()
        return _response({'error': str(e), 'reply': "I'm having a moment — please try again!", 'status': 'error'}, 200)

def _response(body, status=200):
    return {
        'statusCode': status,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST, OPTIONS'
        },
        'body': json.dumps(body)
    }
