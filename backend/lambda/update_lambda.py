import json
import subprocess

# Load Firebase service account
with open(r'C:\Users\sudee\Downloads\her-ai-samantha-firebase-adminsdk-fbsvc-b38944129f.json') as f:
    firebase_data = json.load(f)

firebase_str = json.dumps(firebase_data)

# Your NEW Groq API key — replace this
GROQ_KEY = "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"

# Build environment variables
env_vars = {
    "GROQ_API_KEY": GROQ_KEY,
    "FIREBASE_SERVICE_ACCOUNT": firebase_str
}

env_string = "Variables={" + ",".join([f"{k}={v}" for k,v in env_vars.items()]) + "}"

# Update Lambda
result = subprocess.run([
    'aws', 'lambda', 'update-function-configuration',
    '--function-name', 'her-ai-brain',
    '--environment', env_string,
    '--region', 'ap-south-1'
], capture_output=True, text=True)

if result.returncode == 0:
    print("SUCCESS - Lambda environment updated!")
    print("Groq key set:", GROQ_KEY[:20] + "...")
    print("Firebase account set: YES")
else:
    print("ERROR:", result.stderr)
