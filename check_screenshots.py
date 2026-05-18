import jwt, time, requests

ISSUER_ID = "6dd67287-cfcd-40fc-a3db-8bf378a1ac8f"
KEY_ID = "RJMPC4734X"
APP_ID = "6760955777"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"

with open("AuthKey_RJMPC4734X.p8") as f:
    private_key = f.read()

def make_token():
    payload = {"iss": ISSUER_ID, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})

def hdrs():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}

# Get version ID
r = requests.get(f"{BASE_URL}/apps/{APP_ID}/appStoreVersions", headers=hdrs(), params={"filter[platform]": "IOS", "limit": 1})
versions = r.json().get("data", [])
if not versions:
    print("No versions found")
    exit()

ver = versions[0]
ver_id = ver["id"]
print(f"Version: {ver['attributes']['versionString']} ({ver_id})")

# Get localizations
r2 = requests.get(f"{BASE_URL}/appStoreVersions/{ver_id}/appStoreVersionLocalizations", headers=hdrs())
locs = r2.json().get("data", [])
print(f"Localizations: {len(locs)}")

for loc in locs:
    loc_id = loc["id"]
    locale = loc["attributes"]["locale"]
    # Get screenshots for this localization
    r3 = requests.get(f"{BASE_URL}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", headers=hdrs(), params={"include": "appScreenshots"})
    sets = r3.json().get("data", [])
    total_screenshots = sum(len(s.get("relationships", {}).get("appScreenshots", {}).get("data", [])) for s in sets)
    print(f"  Locale: {locale} - {len(sets)} sets, ~{total_screenshots} screenshots")
    for s in sets:
        display = s["attributes"].get("screenshotDisplayType", "")
        count = len(s.get("relationships", {}).get("appScreenshots", {}).get("data", []))
        print(f"    {display}: {count} screenshots")
