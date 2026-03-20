#!/usr/bin/env python3
"""
Run this script after downloading a new Firebase service account key.

Usage:
    python update_firebase_key.py path/to/new-firebase-key.json

It will:
  1. Read the new key JSON
  2. Update the Lambda FIREBASE_SERVICE_ACCOUNT environment variable
  3. Test the Lambda to confirm it's working
"""
import sys, json, subprocess, os

def main():
    if len(sys.argv) < 2:
        print("Usage: python update_firebase_key.py <path-to-new-firebase-key.json>")
        sys.exit(1)

    key_path = sys.argv[1]
    if not os.path.exists(key_path):
        print(f"ERROR: File not found: {key_path}")
        sys.exit(1)

    # Load and validate the key
    with open(key_path) as f:
        new_key = json.load(f)

    required = ['type', 'project_id', 'private_key_id', 'private_key', 'client_email']
    for field in required:
        if field not in new_key:
            print(f"ERROR: Missing field '{field}' in key JSON")
            sys.exit(1)

    if new_key.get('type') != 'service_account':
        print("ERROR: Not a service account key")
        sys.exit(1)

    print(f"Key loaded: {new_key['client_email']}")
    print(f"Key ID:     {new_key['private_key_id']}")
    print(f"Project:    {new_key['project_id']}")

    # Get current Lambda env vars
    print("\nFetching current Lambda config...")
    result = subprocess.run(
        ['aws', 'lambda', 'get-function-configuration', '--function-name', 'her-ai-brain',
         '--region', 'ap-south-1', '--query', 'Environment.Variables'],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"ERROR: {result.stderr}")
        sys.exit(1)

    env_vars = json.loads(result.stdout)
    env_vars['FIREBASE_SERVICE_ACCOUNT'] = json.dumps(new_key)

    # Write temp env file
    env_payload = {'Variables': env_vars}
    with open('_lambda_env_update.json', 'w') as f:
        json.dump(env_payload, f)

    # Update Lambda
    print("Updating Lambda environment variable...")
    result = subprocess.run(
        ['aws', 'lambda', 'update-function-configuration', '--function-name', 'her-ai-brain',
         '--region', 'ap-south-1', '--environment', 'file://_lambda_env_update.json'],
        capture_output=True, text=True
    )

    # Clean up temp file
    os.remove('_lambda_env_update.json')

    if result.returncode != 0:
        print(f"ERROR updating Lambda: {result.stderr}")
        sys.exit(1)

    config = json.loads(result.stdout)
    print(f"Lambda updated! LastUpdateStatus: {config.get('LastUpdateStatus')}")
    print("\nWait ~10 seconds for Lambda to pick up the new config, then test the app.")
    print("The chat should now work. If it still fails, check the Lambda logs.")

if __name__ == '__main__':
    main()
