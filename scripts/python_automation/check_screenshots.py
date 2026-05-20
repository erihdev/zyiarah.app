import requests
import app_store_common as common

# Get version ID
r = requests.get(f"{common.BASE_URL}/apps/{common.APP_ID}/appStoreVersions", headers=common.hdrs(), params={"filter[platform]": "IOS", "limit": 1})
versions = r.json().get("data", [])
if not versions:
    print("No versions found")
    exit()

ver = versions[0]
ver_id = ver["id"]
print(f"Version: {ver['attributes']['versionString']} ({ver_id})")

# Get localizations
r2 = requests.get(f"{common.BASE_URL}/appStoreVersions/{ver_id}/appStoreVersionLocalizations", headers=common.hdrs())
locs = r2.json().get("data", [])
print(f"Localizations: {len(locs)}")

for loc in locs:
    loc_id = loc["id"]
    locale = loc["attributes"]["locale"]
    # Get screenshots for this localization
    r3 = requests.get(f"{common.BASE_URL}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", headers=common.hdrs(), params={"include": "appScreenshots"})
    sets = r3.json().get("data", [])
    total_screenshots = sum(len(s.get("relationships", {}).get("appScreenshots", {}).get("data", [])) for s in sets)
    print(f"  Locale: {locale} - {len(sets)} sets, ~{total_screenshots} screenshots")
    for s in sets:
        display = s["attributes"].get("screenshotDisplayType", "")
        count = len(s.get("relationships", {}).get("appScreenshots", {}).get("data", []))
        print(f"    {display}: {count} screenshots")
