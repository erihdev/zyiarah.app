"""شهاداتُ توزيعِ App Store Connect: سردُ معرّفاتِها، أو إلغاءُ معرّفاتٍ بعينِها.

الاستعمال: asc_certs.py list | asc_certs.py revoke <id> [<id> ...]
يقرأ المفتاحَ من ASC_KEY_FILE والمعرّفَين من البيئة. لا يُلغي إلّا ما يُسمّى له.
"""
import os
import sys
import time

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com/v1"


def _headers():
    key = open(os.environ["ASC_KEY_FILE"], encoding="utf-8").read()
    token = jwt.encode(
        {
            "iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"],
            "exp": int(time.time()) + 600,
            "aud": "appstoreconnect-v1",
        },
        key,
        algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]},
    )
    return {"Authorization": f"Bearer {token}"}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("list", "revoke"):
        sys.exit(__doc__)
    if sys.argv[1] == "list":
        r = requests.get(
            f"{BASE}/certificates",
            headers=_headers(),
            params={"filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION", "limit": 200},
            timeout=60,
        )
        if r.status_code != 200:
            sys.exit(f"تعذّر سردُ الشهادات: {r.status_code} {r.text[:300]}")
        for c in r.json().get("data", []):
            print(c["id"])
        return
    failed = False
    for cid in sys.argv[2:]:
        r = requests.delete(f"{BASE}/certificates/{cid}", headers=_headers(), timeout=60)
        print(f"إلغاء {cid}: {r.status_code}")
        failed = failed or r.status_code not in (200, 204, 404)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
