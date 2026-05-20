import requests
import app_store_common as common

SUB_ID = "0a51bcf6-383e-4354-8f5a-646aec12226f"

r = requests.get(f"{common.BASE_URL}/reviewSubmissions/{SUB_ID}", headers=common.hdrs())
print("Submission:", r.status_code)
if r.ok:
    data = r.json().get("data", {})
    attrs = data.get("attributes", {})
    print("  State:", attrs.get("state"))
    print("  Submitted:", attrs.get("submitted"))

r2 = requests.get(f"{common.BASE_URL}/apps/{common.APP_ID}/appStoreVersions", headers=common.hdrs(), params={"filter[platform]": "IOS", "limit": 5, "fields[appStoreVersions]": "versionString,appStoreState,createdDate"})
print("Versions:")
for v in r2.json().get("data", []):
    a = v.get("attributes", {})
    print(" ", a.get("versionString"), a.get("appStoreState"), str(a.get("createdDate",""))[:10])
