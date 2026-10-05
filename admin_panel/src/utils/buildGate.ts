// **مرآةُ `lib/utils/build_gate.dart`** — بوّابةُ الإصدار: رقمُ بناءٍ منشورٍ
// واحدٌ يُقرَّر، والصفرُ غياب.
//
// `system_configs/app_update` يُجبرُ العملاءَ على التحديث، وهو **الشرطُ
// المُعلَنُ لنشرِ أربعِ قواعدِ أمانٍ** محجوزةٍ في `firestore.rules` (حجزُ
// STAGE-C). والعطبُ وقعَ مرّتَين، والثانيةُ أدخلَها إصلاحُ الأولى: صارَ
// المحرّرانِ يَكتبانِ حقلَي المنصّةِ، و**الصندوقُ الفارغُ يُكتَبُ صفراً**
// (`parseInt('') || 0` هنا، `int.tryParse('') ?? 0` هناك) — والقارئُ يُفضّلُ
// حقلَ المنصّةِ على الاحتياطيِّ الموحّد، و`currentBuild >= 0` صحيحٌ أبداً،
// فتَموتُ المطالبةُ لتلك المنصّةِ **بصمت** والمفتاحُ يَبدو عاملاً.
//
// ولا بناءَ رقمُه صفرٌ، و«الإطفاءُ» له مفتاحُه (`enabled: false`) — فالصفرُ
// غيابٌ لا قرار. ويَقبلُ النصَّ أيضاً لأنّ حقلَي الإنتاجِ ضُبطا **بيدٍ** في
// الكونسول، وقيمةٌ تُكتَبُ هناك قد تكون نصّاً (نفسُ قصّةِ `promo_codes.expiry`
// بنوعَيها).
//
// ويَحرسُ التطابقَ بين اللغتَين `test/app_update_keys_test.dart`.

/** رقمُ بناءٍ منشورٍ، أو `null` إن لم يُضبَط (صفرٌ/سالبٌ/فارغٌ/غيرُ رقميّ). */
export function publishedBuild(v: unknown): number | null {
  if (typeof v === 'number') {
    const n = Math.trunc(v);
    return Number.isFinite(n) && n > 0 ? n : null;
  }
  if (typeof v === 'string') {
    const t = v.trim();
    if (t === '') return null;
    const n = Number(t);
    return Number.isInteger(n) && n > 0 ? n : null;
  }
  return null;
}

/** أحدثُ بناءٍ منشورٍ لهذه المنصّة: حقلُها، فالموحّدُ، فلا بوّابة. */
export function latestBuildFor(
  d: Record<string, unknown>,
  isIos: boolean,
): number | null {
  const platform = publishedBuild(d[isIos ? 'latest_build_ios' : 'latest_build_android']);
  return platform ?? publishedBuild(d['latest_build']);
}
