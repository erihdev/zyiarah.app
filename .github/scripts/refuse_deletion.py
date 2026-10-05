#!/usr/bin/env python3
"""يَرفضُ حذفَ دالّةٍ من الإنتاجِ صامتاً — حارسٌ صريحٌ بدلَ أثرٍ جانبيٍّ لعلَم.

«حذفُ دالّةٍ قرارٌ بشريٌّ يُنفَّذُ يدويّاً مرّةً واحدة» قرارُ مالكٍ مسجَّل، وكان
يُنفَّذُ **بغيابِ `--force`**: مع `--non-interactive` وحدَها يَفشلُ النشرُ إن
غابت دالّةٌ عن المصدرِ بدلَ أن تُحذَفَ بصمت.

لكنّ `--non-interactive` تَرفضُ كذلك **نشرَ دالّةٍ بسياسةِ إعادةِ محاولة**
(`retry: true`) إلّا بـ`--force` — ومُعالِجا طابورَي الإشعاراتِ يَحملانِها
عمداً («إعادة المحاولة عند فشل عابر (Resend/FCM) بدل فقد الإشعار للأبد»).
فتَصادمَ القرارانِ وتوقّفَ النشرُ كلُّه: **كلُّ** تشغيلٍ منذ 2026-10-05 فشلَ
برسالةٍ واحدة — `Pass the --force option to deploy functions with a failure
policy` — فبقيت كلُّ الإصلاحاتِ الخادميّةِ مدمَجةً وغيرَ عاملةٍ في الإنتاج،
وهي الحفرةُ التي كُتب هذا السيرُ لسدِّها.

فالحمايةُ انتقلَت من **العلَمِ إلى حارسٍ يَقولُ ما يَحرُس**: نقرأُ ما هو
منشورٌ فعلاً، ونَرفضُ النشرَ إن كانت دالّةٌ منشورةٌ قد غابت عن المصدر. وهو
أقوى من العلَم: العلَمُ كان يَحمي بالمصادفةِ (أثرٌ جانبيٌّ لعدمِ التفاعل)
ويَحجبُ النشرَ الشرعيَّ معه؛ وهذا يَحمي بالقصدِ ويَقولُ السبب.

ويَفشلُ **مُغلَقاً**: إن تعذّرَ قراءةُ القائمةِ أو تحليلُها، أو لم يُعثَرْ على
أيِّ تصديرٍ في المصدر، فالخروجُ بفشلٍ — قائمةٌ فارغةٌ تُقرأُ «لا شيءَ يُحذَف»
وهي أخطرُ من خطأ.

الاستعمال: refuse_deletion.py <deployed.json> <functions/index.js>
"""
import json
import re
import sys


def deployed_ids(raw):
    """أسماءُ الدوالِّ المنشورةِ من خَرْجِ `firebase functions:list --json`."""
    a, b = raw.find("{"), raw.rfind("}")
    if a == -1 or b == -1 or b <= a:
        raise ValueError("لا JSON في خَرْجِ functions:list")
    doc = json.loads(raw[a:b + 1])
    result = doc.get("result")
    if not isinstance(result, list):
        raise ValueError("خَرْجُ functions:list بلا result كقائمة")
    out = set()
    for fn in result:
        if not isinstance(fn, dict):
            continue
        fid = fn.get("id") or fn.get("name") or ""
        # بعضُ الصيغِ تُعيدُ مساراً كاملاً — الاسمُ آخرُ مقطع.
        fid = str(fid).rsplit("/", 1)[-1].strip()
        if fid:
            out.add(fid)
    return out


def source_exports(src):
    """أسماءُ `exports.NAME =` في المصدر."""
    code = "\n".join(
        ln for ln in src.split("\n") if not ln.lstrip().startswith("//"))
    return set(re.findall(r"^exports\.([A-Za-z_][A-Za-z0-9_]*)\s*=",
                          code, re.M))


def main(argv):
    if len(argv) != 3:
        print("::error::refuse_deletion.py <deployed.json> <index.js>")
        return 1
    try:
        raw = open(argv[1], encoding="utf-8").read()
        src = open(argv[2], encoding="utf-8").read()
    except OSError as e:
        print("::error::تعذّر قراءةُ مُدخلِ الحارس: %s" % e)
        return 1

    try:
        live = deployed_ids(raw)
    except Exception as e:  # noqa: BLE001 — أيُّ تعذّرٍ يَفشلُ مُغلَقاً
        print("::error::تعذّر تحليلُ قائمةِ الدوالِّ المنشورة (%s). "
              "الحارسُ يَفشلُ مُغلَقاً: قائمةٌ غيرُ مقروءةٍ تُقرأُ «لا شيءَ "
              "يُحذَف» وهي أخطرُ من خطأ." % e)
        return 1

    src_names = source_exports(src)
    if not src_names:
        print("::error::لم يُعثَرْ على أيِّ `exports.` في المصدر — "
              "تحليلٌ معطوبٌ لا مصدرٌ فارغ. الحارسُ يَفشلُ مُغلَقاً.")
        return 1

    # دالّةٌ منشورةٌ وغائبةٌ عن المصدرِ = حذفٌ معلَّق.
    pending = sorted(live - src_names)
    print("منشورةٌ: %d، في المصدر: %d" % (len(live), len(src_names)))
    if not live:
        # مشروعٌ بلا دوالٍّ منشورةٍ = أوّلُ نشر. لا حذفَ ممكن.
        print("لا دوالَّ منشورةً بعد — أوّلُ نشر، ولا حذفَ ممكن.")
        return 0
    if pending:
        print("::error::النشرُ سيَحذفُ من الإنتاج: %s" % ", ".join(pending))
        print("::error::حذفُ دالّةٍ قرارٌ بشريٌّ يُنفَّذُ يدويّاً مرّةً "
              "واحدة. إن كان الحذفُ مقصوداً فنفّذْه بيدك: "
              "`npx firebase-tools@15 deploy --only "
              "functions:<name> --force` أو احذفْها من الكونسول، ثم أعِدْ "
              "تشغيلَ هذا السير.")
        return 1
    print("لا حذفَ معلَّقاً — `--force` آمنٌ في هذا التشغيل.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
