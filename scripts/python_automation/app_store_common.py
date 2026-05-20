import os
import jwt
import time
import requests

def load_env():
    # Look for .env in the parent directory or current directory
    for path in ['.env', '../.env', '../../.env']:
        if os.path.exists(path):
            with open(path) as f:
                for line in f:
                    if '=' in line and not line.startswith('#'):
                        key, val = line.strip().split('=', 1)
                        if val.startswith('"') and val.endswith('"'):
                            val = val[1:-1]
                        elif val.startswith("'") and val.endswith("'"):
                            val = val[1:-1]
                        os.environ[key] = val
            break

# Initialize configuration
load_env()

ISSUER_ID = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "6dd67287-cfcd-40fc-a3db-8bf378a1ac8f")
KEY_ID = os.environ.get("APP_STORE_CONNECT_KEY_ID", "RJMPC4734X")
APP_ID = os.environ.get("APP_STORE_APP_ID", "6760955777")
BASE_URL = "https://api.appstoreconnect.apple.com/v1"
PRIVATE_KEY_PATH = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH", "AuthKey_RJMPC4734X.p8")

# Attempt to locate key file
key_file_paths = [
    PRIVATE_KEY_PATH,
    os.path.join("..", PRIVATE_KEY_PATH),
    os.path.join("../..", PRIVATE_KEY_PATH)
]

private_key = ""
for kp in key_file_paths:
    if os.path.exists(kp):
        with open(kp) as f:
            private_key = f.read()
        break

if not private_key:
    # Codemagic stores file-backed env vars as @file:/path/to/key.p8
    raw_key = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY", "").strip()
    if raw_key.startswith("@file:"):
        file_path = raw_key[len("@file:"):].strip()
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                raw_key = f.read().strip()
    private_key = raw_key

def make_token():
    if not private_key:
        raise ValueError("App Store Connect private key not found!")
    payload = {"iss": ISSUER_ID, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})

def hdrs():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}
