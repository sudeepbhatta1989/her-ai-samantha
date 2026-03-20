"""
agent_loop.py - Samantha autonomous development loop
Uses OpenHands local REST API (runs on localhost:3000)

Architecture:
  1. Starts OpenHands as a Docker container (port 3000)
  2. Configures it with your Groq/Claude API key via REST
  3. Submits tasks from tasks.md via POST /api/conversations
  4. Polls for completion
  5. Sends Telegram approval request
  6. On approval: merges PR via GitHub CLI

Run: python agent_loop.py
"""
import os, subprocess, time, requests, json, sys
from pathlib import Path

try:
    from dotenv import load_dotenv
    _dir = os.path.dirname(os.path.abspath(__file__))
    load_dotenv(os.path.join(_dir, ".env"))
except ImportError:
    pass

# ── Config ────────────────────────────────────────────────────────────────────

TELEGRAM_TOKEN  = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT   = os.getenv("TELEGRAM_CHAT_ID", "")
APP_DIR         = os.getenv("SAMANTHA_APP_DIR", r"C:\Projects\her-ai-samantha\app")
TASKS_FILE      = os.path.join(APP_DIR, "tasks.md")
REPO_SLUG       = "sudeepbhatta1989/her-ai-samantha"
OPENHANDS_URL   = "http://localhost:3000"
CONTAINER_NAME  = "samantha-openhands"

# Choose model
GROQ_KEY   = os.getenv("GROQ_API_KEY", "")
CLAUDE_KEY = os.getenv("ANTHROPIC_API_KEY", "")
GH_TOKEN   = os.getenv("GITHUB_TOKEN", "")

if CLAUDE_KEY:
    LLM_MODEL   = "anthropic/claude-sonnet-4-20250514"
    LLM_API_KEY = CLAUDE_KEY
elif GROQ_KEY:
    LLM_MODEL   = "groq/llama-3.1-70b-versatile"
    LLM_API_KEY = GROQ_KEY
else:
    print("[Agent] ERROR: Set GROQ_API_KEY or ANTHROPIC_API_KEY in .env")
    sys.exit(1)

# ── Telegram ──────────────────────────────────────────────────────────────────

def tg(msg: str):
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT:
        print("[Telegram] " + msg[:120])
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage",
            json={"chat_id": TELEGRAM_CHAT,
                  "text": msg, "parse_mode": "Markdown"},
            timeout=10)
    except Exception as e:
        print(f"[Telegram error] {e}")

# ── Task queue ────────────────────────────────────────────────────────────────

def next_task() -> str | None:
    if not os.path.exists(TASKS_FILE):
        print(f"[Agent] tasks.md not found: {TASKS_FILE}")
        return None
    with open(TASKS_FILE, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("- [ ]"):
                return s[6:].strip()
    return None

def mark_done(task: str):
    _replace_task(task, f"- [x] {task}")

def mark_in_progress(task: str):
    _replace_task(task, f"- [~] {task}")

def mark_failed(task: str):
    # Restore to pending
    with open(TASKS_FILE, encoding="utf-8") as f:
        c = f.read()
    with open(TASKS_FILE, "w", encoding="utf-8") as f:
        f.write(c
            .replace(f"- [~] {task}", f"- [ ] {task}", 1))

def _replace_task(task: str, replacement: str):
    with open(TASKS_FILE, encoding="utf-8") as f:
        c = f.read()
    with open(TASKS_FILE, "w", encoding="utf-8") as f:
        f.write(c.replace(f"- [ ] {task}", replacement, 1)
                 .replace(f"- [~] {task}", replacement, 1))

# ── OpenHands Docker ──────────────────────────────────────────────────────────

def is_openhands_running() -> bool:
    try:
        r = requests.get(f"{OPENHANDS_URL}/api/options/models", timeout=5)
        return r.status_code < 500
    except Exception:
        return False

def start_openhands():
    """Start OpenHands Docker container if not already running."""
    # Check if container already running
    r = subprocess.run(
        f"docker ps --filter name={CONTAINER_NAME} --format {{{{.Names}}}}",
        shell=True, capture_output=True, text=True)
    if CONTAINER_NAME in r.stdout:
        print("[Agent] OpenHands container already running", flush=True)
        return True

    # Windows path for Docker volume mount
    app_mount = APP_DIR.replace("\\", "/")
    if app_mount[1] == ":":  # C:/ -> /c/
        app_mount = "/" + app_mount[0].lower() + app_mount[2:]

    print("[Agent] Starting OpenHands container...", flush=True)
    cmd = (
        f"docker run -d "
        f"--name {CONTAINER_NAME} "
        f"-p 3000:3000 "
        f"-v //var/run/docker.sock:/var/run/docker.sock "
        f"-v \"{APP_DIR}:/.openhands-workspace\" "
        f"-e SANDBOX_RUNTIME_CONTAINER_IMAGE=ghcr.io/all-hands-ai/runtime:main "
        f"-e LOG_ALL_EVENTS=true "
        f"--add-host host.docker.internal:host-gateway "
        f"ghcr.io/all-hands-ai/openhands:main"
    )
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"[Agent] Docker start error: {r.stderr[:300]}", flush=True)
        return False

    # Wait for server to be ready
    print("[Agent] Waiting for OpenHands to start (up to 60s)...", flush=True)
    for i in range(60):
        time.sleep(2)
        if is_openhands_running():
            print(f"[Agent] OpenHands ready after {(i+1)*2}s", flush=True)
            return True
        if i % 5 == 4:
            print(f"[Agent] Still waiting... ({(i+1)*2}s)", flush=True)

    print("[Agent] OpenHands failed to start in 60s", flush=True)
    return False

def stop_openhands():
    subprocess.run(
        f"docker stop {CONTAINER_NAME} && docker rm {CONTAINER_NAME}",
        shell=True, capture_output=True)

def configure_openhands():
    """Set LLM API key and model via REST API."""
    payload = {
        "llm_model":   LLM_MODEL,
        "llm_api_key": LLM_API_KEY,
    }
    if "groq" in LLM_MODEL:
        payload["llm_base_url"] = "https://api.groq.com/openai/v1"

    try:
        r = requests.post(
            f"{OPENHANDS_URL}/api/settings",
            json=payload, timeout=10)
        if r.status_code in (200, 201):
            print(f"[Agent] LLM configured: {LLM_MODEL}", flush=True)
            return True
        else:
            print(f"[Agent] Settings warning: {r.status_code} {r.text[:100]}", flush=True)
            return True  # non-fatal, continue
    except Exception as e:
        print(f"[Agent] Configure error: {e}", flush=True)
        return False

# ── Run task via OpenHands API ────────────────────────────────────────────────

def run_task(task: str) -> bool:
    """Submit task to OpenHands and wait for completion."""
    print(f"\n[Agent] Submitting task to OpenHands...", flush=True)
    print(f"[Agent] Task: {task[:80]}", flush=True)

    # Build task with full context
    full_task = (
        f"You are working on the Samantha AI iOS app project.\n"
        f"Repository: https://github.com/{REPO_SLUG}\n"
        f"Workspace: /.openhands-workspace\n\n"
        f"TASK: {task}\n\n"
        f"Instructions:\n"
        f"1. Analyse the relevant files in the workspace\n"
        f"2. Make the required code changes\n"
        f"3. Run any tests if applicable\n"
        f"4. Create a git branch named 'openhands/{task[:40].lower().replace(' ','-').replace(':','')}\n"
        f"5. Commit changes with a clear message\n"
        f"6. The changes will be reviewed before merging\n"
    )

    # Create conversation
    try:
        r = requests.post(
            f"{OPENHANDS_URL}/api/conversations",
            json={"initial_user_msg": full_task},
            timeout=30)

        if r.status_code not in (200, 201):
            print(f"[Agent] Create conversation failed: {r.status_code} {r.text[:200]}")
            return False

        data = r.json()
        conv_id = data.get("conversation_id") or data.get("id")
        if not conv_id:
            print(f"[Agent] No conversation ID in response: {data}")
            return False

        print(f"[Agent] Conversation started: {conv_id}", flush=True)
        print(f"[Agent] Watch live at: {OPENHANDS_URL}/conversations/{conv_id}", flush=True)
        tg(f"*OpenHands working on:*\n`{task[:80]}`\n\n"
           f"Watch live: {OPENHANDS_URL}/conversations/{conv_id}")

    except Exception as e:
        print(f"[Agent] API error: {e}", flush=True)
        return False

    # Poll for completion
    print("[Agent] Polling for completion (max 30 min)...", flush=True)
    deadline = time.time() + 1800  # 30 min
    last_status = ""

    while time.time() < deadline:
        time.sleep(15)
        try:
            r = requests.get(
                f"{OPENHANDS_URL}/api/conversations/{conv_id}",
                timeout=10)
            if r.status_code != 200:
                continue

            data = r.json()
            status = data.get("status", "unknown")

            if status != last_status:
                print(f"[Agent] Status: {status}", flush=True)
                last_status = status

            if status in ("stopped", "finished", "completed"):
                print(f"[Agent] Task finished with status: {status}", flush=True)
                return True

            if status in ("error", "failed"):
                print(f"[Agent] Task failed with status: {status}", flush=True)
                return False

        except Exception as e:
            print(f"[Agent] Poll error: {e}", flush=True)

    print("[Agent] Task timed out (30 min)", flush=True)
    tg(f"*Task timed out (30min)*\n`{task[:80]}`")
    return False

# ── Approval ──────────────────────────────────────────────────────────────────

def wait_approval(task: str) -> bool:
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT:
        print("\n[Agent] No Telegram — manual approval mode")
        answer = input("Approve this change? (y/n): ").strip().lower()
        return answer == "y"

    tg(
        f"*Task complete — approve merge?*\n"
        f"`{task[:100]}`\n\n"
        f"Review PR: https://github.com/{REPO_SLUG}/pulls\n\n"
        f"Reply /approve to merge\n"
        f"Reply /reject to close PR"
    )
    print("[Agent] Waiting for Telegram approval (1hr timeout)...", flush=True)

    offset = None
    deadline = time.time() + 3600

    while time.time() < deadline:
        try:
            params = {"timeout": 30}
            if offset:
                params["offset"] = offset
            r = requests.get(
                f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/getUpdates",
                params=params, timeout=35).json()
            for upd in r.get("result", []):
                offset = upd["update_id"] + 1
                text = upd.get("message", {}).get("text", "")
                if "/approve" in text.lower():
                    tg("*Approved!* Merging PR...")
                    return True
                if "/reject" in text.lower():
                    tg("*Rejected.* Closing PR.")
                    return False
        except Exception as e:
            print(f"[Agent] Telegram poll error: {e}")
            time.sleep(10)

    tg("*Approval timeout (1hr).* Closing PR.")
    return False

# ── Git ───────────────────────────────────────────────────────────────────────

def push_branch_and_pr(task: str):
    """Push any local changes OpenHands made and open a PR."""
    branch = "openhands/" + task[:40].lower().replace(" ","-").replace(":","")[:35]

    # Push branch
    subprocess.run(f"git push origin {branch}",
                   shell=True, cwd=APP_DIR, capture_output=True)

    # Create PR
    pr_body = (
        f"## Automated PR by Samantha Agent\n\n"
        f"**Task:** {task}\n\n"
        f"**Agent:** OpenHands + {LLM_MODEL}\n\n"
        f"---\n*Review and approve via Telegram or GitHub UI*"
    )
    subprocess.run(
        f'gh pr create --title "[OpenHands] {task[:60]}" '
        f'--body "{pr_body}" --base master --head {branch}',
        shell=True, cwd=APP_DIR, capture_output=True)

def merge_pr():
    r = subprocess.run(
        "gh pr merge --auto --squash --delete-branch",
        shell=True, cwd=APP_DIR, capture_output=True, text=True)
    if r.returncode == 0:
        print("[Agent] PR merged successfully", flush=True)
    else:
        print(f"[Agent] PR merge note: {r.stderr[:100]}", flush=True)

def close_pr():
    subprocess.run("gh pr close --delete-branch",
                   shell=True, cwd=APP_DIR, capture_output=True)

# ── Main loop ─────────────────────────────────────────────────────────────────

def main():
    print("=" * 56, flush=True)
    print("[Samantha Agent Loop] Starting", flush=True)
    print(f"Tasks:  {TASKS_FILE}", flush=True)
    print(f"App:    {APP_DIR}", flush=True)
    print(f"Model:  {LLM_MODEL}", flush=True)
    print(f"OpenHands: {OPENHANDS_URL}", flush=True)
    print("=" * 56, flush=True)
    print("Press Ctrl+C to stop\n", flush=True)

    # Start OpenHands server
    if not start_openhands():
        print("[Agent] Could not start OpenHands. Exiting.")
        sys.exit(1)

    # Configure LLM
    configure_openhands()

    tg(
        f"*Samantha Agent Loop started*\n"
        f"Model: `{LLM_MODEL}`\n"
        f"OpenHands: {OPENHANDS_URL}\n\n"
        f"Ready to process tasks."
    )

    fail_count = 0

    try:
        while True:
            task = next_task()
            if not task:
                print("[Agent] No pending tasks. Checking in 5 min...", flush=True)
                time.sleep(300)
                fail_count = 0
                continue

            if fail_count >= 3:
                tg(f"*3 failures on task — skipping:*\n`{task[:80]}`")
                mark_done(task)  # mark done to unblock queue
                fail_count = 0
                continue

            mark_in_progress(task)
            ok = run_task(task)

            if not ok:
                mark_failed(task)
                fail_count += 1
                wait_secs = 60 * fail_count
                tg(f"*Task failed* (attempt {fail_count}/3)\n`{task[:80]}`\nRetrying in {wait_secs}s...")
                print(f"[Agent] Failed (attempt {fail_count}/3). Retry in {wait_secs}s...", flush=True)
                time.sleep(wait_secs)
                continue

            fail_count = 0

            # Try to push branch and create PR
            push_branch_and_pr(task)

            approved = wait_approval(task)
            if approved:
                mark_done(task)
                merge_pr()
                tg("*Merged!* Starting next task soon.")
            else:
                mark_failed(task)
                close_pr()
                tg("*PR closed.* Task moved back to pending.")

            time.sleep(5)

    except KeyboardInterrupt:
        print("\n[Agent] Stopping...", flush=True)
        tg("*Samantha Agent stopped* (Ctrl+C)")

if __name__ == "__main__":
    main()
