import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

// ════════════════════════════════════════════════════════════════════════
// **سرٌّ يَستهلكُه مسارُ إصدارٍ بلا فحصِ حضورٍ قبلَه (2026-11-01).**
//
// القاعدةُ مسجَّلةٌ في CLAUDE.md ومُنفَّذةٌ في المستودعِ قبلَ هذا الحارسِ:
// «السرُّ الغائبُ **يُفشِلُ الوظيفةَ** لا يُكتَبُ فارغاً». وعلّتُها أنّ
// `echo "$غيرُ_مضبوط" > ملفّ` **يَخرُجُ بصفر** ويُنشئُ ملفاً بسطرٍ فارغ،
// فالعلامةُ الخضراءُ على خطوةِ «كتابةِ السرّ» ليست دليلاً أنّ السرَّ موجود:
// خمسُ دمجاتٍ في 31 أكتوبر قرأت «Write certificate private key: OK» ثمّ
// فشلت عند `fetch-signing-files` بعدَها بأربعِ ثوانٍ بلا سببٍ مقروء.
//
// **ولمَ أُعيد بناءُ الحارسِ من أساسِه:** صياغتُه الأولى سألت «أهذا السطرُ
// كتابةُ ملفٍّ لسرّ؟» فعدَّدت أشكالَ الكتابةِ (توجيهٌ، `tee`، `dd of=`،
// `install /dev/stdin`، مُفسِّرٌ يَكتبُ مساراً). ومسحٌ هجوميٌّ بأربعينَ
// وكيلاً أثبتَ **إحدى وعشرينَ** صيغةً تُعيدُ العطلَ كاملاً والحارسُ أخضر:
// `cp /dev/stdin`، و`openssl -out`، و`git config --file`، و`sed -i`،
// و`perl -pi`، و`appendFileSync`، وheredoc إلى أمرٍ ليس كتابةً، و`exec >
// ملفّ` ثمّ `echo "$سرّ"` على سطرٍ تالٍ، و`exec 3> ملفّ` ثمّ `>&3`…
// وأسوأُها أنّ **صيغةَ المستودعِ نفسِه** — `python3 - <<'PY'` في
// `codemagic.yaml:73` — كانت غيرَ مرئيّةٍ للكاشف.
//
// فالعلّةُ بنيويّةٌ لا قائمةُ ثقوب: «ما هي كتابةُ ملفّ؟» **مجموعةٌ مفتوحةٌ**
// لا تَكتملُ أبداً، وكانت على الجهةِ التي **تَفشلُ مفتوحةً** — شكلٌ مجهولٌ
// ⇒ غيرُ مرئيٍّ ⇒ أخضر. وكذلك كانت بقيّةُ مجموعاتِه: تهجئةٌ مجهولةٌ لقراءةِ
// البيئةِ ⇒ «لا سرَّ هنا»، وYAML غيرُ قانونيٍّ ⇒ «لا خطواتِ»، واسمٌ مُعلَنٌ
// في أيِّ موضعٍ ⇒ يَخرُجُ من «السرّ».
//
// **الأساسُ الجديد:** لا كشفَ للكتابةِ إطلاقاً. القاعدةُ أنّ **كلَّ سرٍّ
// يُذكَرُ اسمُه في جسمِ خطوةِ إصدارٍ يَجبُ أن يُفحَصَ حضورُه قبلَ أوّلِ
// ذكرٍ له** — وهو ما يَفعلُه المستودعُ فعلاً: `android_release.yml` يَفحصُ
// أسرارَه الستّةَ كلَّها، ولا واحدٌ منها بسببِ كتابةِ ملفّ. و«أيُذكَرُ
// اسمُ السرِّ في هذا الجسم؟» سؤالٌ **مُغلَق**: أيُّ آليّةٍ تَقرأُ متغيّرَ
// بيئةٍ لا بُدَّ أن تُسمّيَه. ولا يَعنينا بعدَ ذلك ماذا يَفعلُ به السطرُ —
// كتابةً كان أو وسيطَ أمرٍ أو ترويسةَ طلب: الغيابُ يُفشِلُ الثلاثةَ بلا
// سببٍ مقروء.
//
// **وكلُّ مجموعةٍ مفتوحةٍ باقيةٍ نُقِلت إلى الجهةِ التي تَفشلُ مُغلَقةً:**
//   • شكلُ بوّابةٍ مجهولٌ ⇒ **ليس بوّابةً** ⇒ أحمر (لا «قد تكون»).
//   • تعذُّرُ تحليلِ YAML ⇒ أحمر (لا «صفرُ خطوات»).
//   • سكربتٌ أو إجراءٌ محلّيٌّ لا يُقرَأُ ⇒ أحمر (لا تخطٍّ صامت).
//   • اسمٌ كبيرٌ في جسمٍ ليس في قائمةِ الأسرارِ ولا في قائمةِ غيرِ الأسرار
//     ⇒ أحمر («أسِرٌّ هو؟») — فسرٌّ جديدٌ يَدخلُ الفحصَ بنفسِه.
// فما يَستطيعُه مُهاجِمٌ الآن أن يُحمِّرَ الحارسَ، لا أن يُخفيَ سرّاً.
//
// **ومجموعةُ الأسرارِ مثبَّتةٌ هنا لا مُستنتَجةٌ من الملفّ** — وذاك وحدَه
// يُلغي أربعَ صيغٍ مُثبَتةٍ كانت تُسقِطُ اسماً من «السرّ» بإعلانِه: سطرُ
// `NAME: ""` في `vars:`، وإعادةُ تصديرٍ لنفسِه `X="$X"`، وإعلانٌ في سيرٍ
// **آخرَ** داخلَ الملفِّ نفسِه، وإسنادٌ محلّيٌّ باسمِ السرِّ.
// ════════════════════════════════════════════════════════════════════════

/// أسرارُ مسارِ الإصدارِ ومصدرُ كلٍّ. مثبَّتةٌ عمداً: الاستنتاجُ من الملفِّ
/// هو ما كان يُهاجَم. و`codemagic.yaml` لا يُعلِنُ أسماءَ أسرارِه أصلاً
/// (تَسكنُ `groups:` في لوحةِ Codemagic)، فلا سبيلَ إلى اشتقاقِها منه.
const kReleaseSecrets = <String, String>{
  // مجموعةُ `appstore_credentials` في Codemagic، و`secrets.*` في سِيَرِ الوسم.
  'APP_STORE_CONNECT_ISSUER_ID': 'appstore_credentials / secrets',
  'APP_STORE_CONNECT_KEY_ID': 'appstore_credentials / secrets',
  'APP_STORE_CONNECT_PRIVATE_KEY': 'appstore_credentials / secrets',
  // مفتاحُ الشهادةِ الخاصُّ — مُدخَلُ `fetch-signing-files`، وهو الخطوةُ
  // العاشرةُ التي يَفشلُ عندَها بناءُ iOS منذ 31 أكتوبر.
  'CERTIFICATE_PRIVATE_KEY': 'appstore_credentials',
  // توقيعُ أندرويد.
  'ANDROID_KEYSTORE_BASE64': 'android_credentials / secrets',
  'ANDROID_KEYSTORE_PASSWORD': 'android_credentials',
  'ANDROID_KEY_PASSWORD': 'android_credentials / secrets',
  'ANDROID_KEY_ALIAS': 'android_credentials',
  'ANDROID_STORE_PASSWORD': 'secrets (سيرُ الوسم)',
  // مفاتيحُ `.env` القابلةُ للنشرِ — سرٌّ بمعنى «غيابُها يُعطِبُ البناءَ
  // بصمت» لا بمعنى «لا يَجوزُ أن تُرى»: غيابُ مفتاحِ ميسر يُنتجُ حزمةً بلا
  // بطاقةٍ ولا Apple Pay، وبناءً أخضر.
  'MOYASAR_PUBLISHABLE_KEY': 'payment_keys / secrets',
  'MAPBOX_TOKEN': 'payment_keys / appstore_credentials / secrets',
  'SAMSUNG_PAY_SERVICE_ID': 'payment_keys / secrets',
  // النشرُ.
  'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON': 'secrets (سيرُ الوسم)',
  'GCLOUD_SERVICE_ACCOUNT_CREDENTIALS': 'google_play (Codemagic)',
  'FIREBASE_SERVICE_ACCOUNT': 'secrets (سِيَرُ النشر)',
};

/// أسماءٌ كبيرةٌ ليست أسراراً — إعدادٌ مُعلَنٌ في الملفِّ، أو متغيّرٌ
/// يُوفّرُه المُشغّل. **القائمةُ مثبَّتةٌ** كي لا يُعَدَّ سرٌّ جديدٌ «إعداداً»
/// بمجردِ أن يُعلَنَ في `vars:`.
const kNonSecretNames = <String, String>{
  'APP_STORE_APP_ID': 'إعدادٌ مُعلَنٌ: codemagic.yaml "6760955777"',
  'PACKAGE_NAME': 'إعدادٌ مُعلَنٌ: codemagic.yaml "com.zyiarah.zyiarah"',
  'BUNDLE_ID': 'إعدادٌ مُعلَنٌ: codemagic.yaml',
  'CM_ENV': 'يُوفّرُه Codemagic',
  'CM_BUILD_DIR': 'يُوفّرُه Codemagic',
  'FCI_BUILD_ID': 'يُوفّرُه Codemagic',
  'GITHUB_ENV': 'يُوفّرُه مُشغّلُ Actions',
  'GITHUB_OUTPUT': 'يُوفّرُه مُشغّلُ Actions',
  'GITHUB_STEP_SUMMARY': 'يُوفّرُه مُشغّلُ Actions',
  'GITHUB_SHA': 'يُوفّرُه مُشغّلُ Actions',
  'GITHUB_REF': 'يُوفّرُه مُشغّلُ Actions',
  'RUNNER_TEMP': 'يُوفّرُه مُشغّلُ Actions',
  'HOME': 'بيئةُ POSIX',
  'PATH': 'بيئةُ POSIX',
  'PWD': 'بيئةُ POSIX',
  'PYTHONPATH': 'بيئةُ POSIX',
  'TMPDIR': 'بيئةُ POSIX',
};

/// مواضعُ يُذكَرُ فيها سرٌّ بلا بوّابةٍ صارمة — **بسببٍ مكتوبٍ وشاهدٍ
/// مفحوص**. المفتاحُ `ملفّ|اسمُ الخطوة|السرّ`.
const kUngatedAllowed = <String, String>{
  // الزرُّ يُخفى في التطبيقِ عند غيابِ السرِّ أو عند قيمةٍ نائبة
  // (`nativePayPlaceholder` في `lib/utils/native_pay_config.dart`)، فالغيابُ
  // تدهوُرٌ **ظاهرٌ ومقصود** لا عطلٌ صامت. والشاهدُ أنّ تلك القاعدةَ قائمة.
  'codemagic.yaml|Create .env file|SAMSUNG_PAY_SERVICE_ID': 'تدهوُرٌ ظاهرٌ',
  '.github/workflows/android_release.yml|Create .env|SAMSUNG_PAY_SERVICE_ID':
      'تدهوُرٌ ظاهرٌ',
  '.github/workflows/ios_release.yml|Create .env file|SAMSUNG_PAY_SERVICE_ID':
      'تدهوُرٌ ظاهرٌ',
  // خطوةٌ **غيرُ قاتلةٍ بإعلانِها** (`ignore_failure: true`) ومعها فرعُ
  // تخطٍّ صريحٌ يَخرُجُ بصفرٍ عند غيابِ السرّ. فبوّابةٌ صارمةٌ هنا تَقلبُ
  // قراراً موثَّقاً: إلغاءُ المراجعةِ أفضلُ جهدٍ لا شرطُ إصدار.
  'codemagic.yaml|Cancel existing App Store review submissions|APP_STORE_CONNECT_ISSUER_ID':
      'أفضلُ جهدٍ: ignore_failure + فرعُ تخطٍّ',
  'codemagic.yaml|Cancel existing App Store review submissions|APP_STORE_CONNECT_KEY_ID':
      'أفضلُ جهدٍ: ignore_failure + فرعُ تخطٍّ',
  'codemagic.yaml|Cancel existing App Store review submissions|APP_STORE_CONNECT_PRIVATE_KEY':
      'أفضلُ جهدٍ: ignore_failure + فرعُ تخطٍّ',
};

/// جسمُ أمرٍ في مسارِ إصدار.
class ShellBody {
  ShellBody(this.file, this.job, this.step, this.text, this.aliases,
      this.nonFatal, this.extra, this.envKeys);

  final String file;
  final String job;
  final String step;

  /// نصُّ الجسمِ كما هو في الملفّ.
  final String text;

  /// الاسمُ المحلّيُّ ← السرُّ المربوطُ به في `env:` الخطوة.
  final Map<String, String> aliases;

  /// الخطوةُ مُعلَنةٌ غيرَ قاتلة (`ignore_failure` / `continue-on-error`).
  final bool nonFatal;

  /// أجسامٌ تَبعتها الخطوةُ بالإحالة (سكربتٌ أو إجراءٌ محلّيّ).
  final List<String> extra;

  /// كلُّ مفاتيحِ `env:` للخطوةِ والوظيفة — **مُعلَنةٌ في الملفِّ** أيّاً
  /// كان ما تَربطُه، فليست قراءةَ بيئةٍ مجهولة. وربطُها بسرٍّ لا يُنجّيها:
  /// `aliases` تُسجّلُه، فالقاعدةُ تَطلبُ بوّابةً على الاسمِ المحلّيِّ.
  final Set<String> envKeys;

  String get key => '$file|$step';
  String get all => ([text, ...extra]).join('\n');
}

/// يُبدِلُ محتوى النصوصِ المُقتبَسةِ مسافاتٍ **بحفظِ الإزاحات**، كي يُفحَصَ
/// **تركيبُ** كتلةِ البوّابةِ لا محتوى رسائلِها: قوسٌ داخلَ رسالةٍ عربيّةٍ
/// ليس صدفةً فرعيّة، و`exit` داخلَ نصٍّ ليس خروجاً.
String blankQuoted(String s) {
  final out = s.split('');
  var q = 0; // 0=خارج 1=مفرد 2=مزدوج
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (q == 0 && (c == "'" || c == '"')) {
      q = c == "'" ? 1 : 2;
      out[i] = ' ';
    } else if (q == 1 && c == "'") {
      q = 0;
      out[i] = ' ';
    } else if (q == 2 && c == '"') {
      if (i > 0 && s[i - 1] == r'\') continue;
      q = 0;
      out[i] = ' ';
    } else if (q != 0) {
      out[i] = c == '\n' ? '\n' : ' ';
    }
  }
  return out.join();
}

/// يَحجبُ أسطرَ التعليقِ **بمسافاتٍ** لا بحذفٍ، فالإزاحاتُ تَبقى مُطابِقةً
/// للنصِّ الأصليِّ — فمقارنةُ موضعِ البوّابةِ بموضعِ أوّلِ ذكرٍ تَبقى صحيحة.
String maskComments(String s) => s
    .split('\n')
    .map((l) => l.trimLeft().startsWith('#') ? ' ' * l.length : l)
    .join('\n');

/// نطاقُ **البوّابةِ القانونيّةِ** على الرمزِ `tok`، أو `null`.
///
/// ثلاثةُ أشكالٍ مقبولةٌ فقط، وما ليس منها **ليس بوّابة** — فالمجموعةُ
/// المفتوحةُ («ما قد يَكونُ فحصاً») نُقِلت إلى الجهةِ التي تَفشلُ مُغلَقةً.
/// وثلاثُ صيغٍ مُثبَتةٍ كانت تَفوزُ على فحصٍ أرخى، وكلُّها مرفوضةٌ هنا:
///   • صدفةٌ فرعيّةٌ `( exit 1 )` — الخروجُ يُنهي الصدفةَ لا الخطوة.
///   • شرطٌ متداخلٌ لا يَصدُقُ أبداً حولَ `exit`.
///   • فرعُ `else` — الخروجُ في الجهةِ الخاطئة.
/// وقُطبيّةُ الشرطِ مثبَّتةٌ: `[ -z "$TOK" ]` حرفيّاً، فلا `!` ولا `&&`
/// يَجعلانِ فحصاً يَصدُقُ عند **حضورِ** السرِّ يُقرأُ فحصَ حضور.
List<int>? canonicalGate(String body, String tok) {
  final t = RegExp.escape(tok);

  // (ج) الصيغةُ القياسيّةُ في POSIX: الصدفةُ تَخرُجُ بخطأٍ يُسمّي المتغيّر.
  final posix = RegExp(r'\$\{' + t + r':\?').firstMatch(body);
  if (posix != null) return [posix.start, posix.end];

  // (أ) `if [ -z "$TOK" ]; then … exit N … fi`
  final head = RegExp(r'(?:^|\n|;|&&|\|\|)\s*if\s+(?:\[|test)\s+-z\s+'
          r'"?\$\{?@T\}?"?\s*\]?\s*;?\s*then\b'
      .replaceAll('@T', t));
  for (final m in head.allMatches(body)) {
    final rest = body.substring(m.end);
    final fi = RegExp(r'(?:^|\n|;)\s*fi\b').firstMatch(rest);
    if (fi == null) continue;
    final blk = blankQuoted(rest.substring(0, fi.start));
    if (blk.contains('(')) continue;
    if (RegExp(r'\belse\b').hasMatch(blk)) continue;
    if (RegExp(r'\bif\b').hasMatch(blk)) continue;
    if (!RegExp(r'\bexit\s+[1-9]').hasMatch(blk)) continue;
    final at = body.indexOf(tok, m.start);
    if (at < 0 || at > m.end) continue;
    return [m.start, at + tok.length];
  }

  // (ب) حلقةٌ على أسماءٍ، وجسمُها بوّابةُ الشكلِ (أ) على قيمةِ الحلقة.
  final forRe = RegExp(r'\bfor\s+(\w+)\s+in\s+([^\n;]+?)\s*;?\s*do\b');
  for (final f in forRe.allMatches(body)) {
    final list = f.group(2)!;
    if (!RegExp(r'(?<![A-Za-z0-9_])' + t + r'(?![A-Za-z0-9_])').hasMatch(list)) {
      continue;
    }
    final rest = body.substring(f.end);
    final done = RegExp(r'(?:^|\n|;)\s*done\b').firstMatch(rest);
    if (done == null) continue;
    final loop = rest.substring(0, done.start);
    final ev = RegExp(r'\beval\s+"?(\w+)=\\?\$+' + RegExp.escape(f.group(1)!))
        .firstMatch(loop);
    final valVar = ev?.group(1) ?? 'val';
    if (canonicalGate(loop, valVar) == null) continue;
    final at = body.indexOf(tok, f.start);
    if (at < 0) continue;
    return [f.start, at + tok.length];
  }
  return null;
}

final _envForms = <RegExp>[
  RegExp(r'\$\{?([A-Z][A-Z0-9_]{3,})\}?'),
  RegExp(r"""(?:environ|ENV)\s*(?:\[|\.get\s*\()\s*['"]([A-Z][A-Z0-9_]{3,})['"]"""),
  RegExp(r"""\bgetenv\s*\(\s*['"]([A-Z][A-Z0-9_]{3,})['"]"""),
  RegExp(r"""\bENV\s*\{\s*['"]?([A-Z][A-Z0-9_]{3,})"""),
  RegExp(r'\bprintenv\s+([A-Z][A-Z0-9_]{3,})'),
  RegExp(r'\bprocess\.env\.([A-Z][A-Z0-9_]{3,})'),
  RegExp(r'\bENV\.([A-Z][A-Z0-9_]{3,})'),
];

/// كلُّ اسمٍ يَقرؤه الجسمُ من البيئة. السؤالُ **مُغلَق**: أيُّ آليّةٍ تَقرأُ
/// متغيّرَ بيئةٍ لا بُدَّ أن تُسمّيَه، فتوسيعُ قائمةِ الصيغِ لا يُنتجُ
/// ثقباً — وما تُخطئُه صيغةٌ يُمسِكُه الشكلُ الأوّلُ (`$NAME`).
Set<String> envNamesIn(String body) {
  final s = maskComments(body);
  final out = <String>{};
  for (final re in _envForms) {
    for (final m in re.allMatches(s)) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

Set<String> locallyAssigned(String body) {
  final s = maskComments(body);
  return <String>{
    // الإسنادُ لا يَلزمُ أن يَبدأَ سطراً: `if ! PATHS=$(…)` و`A=1 B=2 cmd`
    // كلاهما إسنادٌ صحيحٌ، وصياغةٌ مُرتكِزةٌ على بدايةِ السطرِ أبلغَت عنهما
    // «قراءةَ بيئةٍ مجهولة».
    ...RegExp(r'(?:^|[\s;!&|(])(?:export\s+)?([A-Z][A-Z0-9_]{3,})=',
            multiLine: true)
        .allMatches(s)
        .map((m) => m.group(1)!),
    ...RegExp(r'\bfor\s+([A-Z][A-Z0-9_]{3,})\s+in\b')
        .allMatches(s)
        .map((m) => m.group(1)!),
  };
}

bool _truthy(Object? v) => v == true || v == 'true';

/// **صنفُ المسارِ الذي أعماها:** صياغةٌ أولى شرطت حرفاً أبجديّاً أوّلَ
/// المسار، فـ`bash .github/scripts/x.sh` — مجلّدُ سكربتاتِ المستودعِ
/// نفسِه — لم يُتَّبَعْ قطّ، وكشفَه فحصُ الكاشفِ لا المراجعة.
final _invokeRe = <RegExp>[
  RegExp(r'\b(?:bash|sh|source)\s+"?([A-Za-z0-9_./][A-Za-z0-9_./-]*\.sh)"?'),
  RegExp(r'(?:^|\n|;|&&|\|\|)\s*"?(\.{1,2}/[A-Za-z0-9_./-]*\.sh)"?'),
];

/// **الإحالةُ تُتبَعُ، وما لا يُقرَأُ يُحمِّرُ.** صيغتانِ مُثبَتتانِ كانتا
/// تُخرِجانِ الكتابةَ من النظرِ كلّيّاً: سكربتُ صدفةٍ يُنادى من الخطوة،
/// وإجراءٌ محلّيٌّ (`uses: ./…`) يَتولّى الكتابةَ. فتخطٍّ صامتٌ هنا هو
/// الثقبُ نفسُه بثوبٍ آخر.
List<String> followScripts(String file, String step, String text) {
  final out = <String>[];
  final seen = <String>{};
  for (final re in _invokeRe) {
    for (final m in re.allMatches(maskComments(text))) {
      var p = m.group(1)!;
      while (p.startsWith('./')) {
        p = p.substring(2);
      }
      if (!seen.add(p)) continue;
      final f = File(p);
      if (!f.existsSync()) {
        throw StateError('$file ← $step: يُنادي «$p» ولا يُقرَأُ — '
            'فالكتابةُ فيه خارجَ النظرِ كلّيّاً');
      }
      out.add(f.readAsStringSync());
    }
  }
  return out;
}

String readLocalAction(String file, String step, String uses) {
  final dir = uses.replaceFirst(RegExp(r'^\./'), '').split('@').first;
  for (final n in ['action.yml', 'action.yaml']) {
    final f = File('$dir/$n');
    if (!f.existsSync()) continue;
    dynamic a;
    try {
      a = loadYaml(f.readAsStringSync());
    } catch (e) {
      throw StateError('$file ← $step: «$dir/$n» لا يُحلَّل — $e');
    }
    final runs = a is Map ? a['runs'] : null;
    final steps = runs is Map ? runs['steps'] : null;
    final b = <String>[];
    if (steps is List) {
      for (final s in steps) {
        if (s is Map && s['run'] is String) b.add(s['run'] as String);
      }
    }
    return b.join('\n');
  }
  throw StateError('$file ← $step: `uses: $uses` ولا `action.yml` يُقرَأُ — '
      'فكتابةُ الإجراءِ خارجَ النظر');
}

/// أجسامُ الأوامرِ في ملفٍّ واحد. **تحليلٌ حقيقيٌّ للـYAML**: عَدُّ
/// الخطواتِ بالنصِّ أعمى ثلاثَ مرّاتٍ مُثبَتةً — مَسرَدٌ بإزاحةِ صفر،
/// ورمزٌ زائدٌ على سطرِ `steps:`، ومِرساةُ YAML مُعرَّفةٌ خارجَ الخطوات —
/// وفي الثلاثةِ كان الناتجُ «صفرَ خطواتٍ» أي أخضرَ. وتعذُّرُ التحليلِ
/// **يَرمي** الآن لا يُعيدُ فراغاً.
List<ShellBody> bodiesOf(String file, String src, {required bool gh}) {
  dynamic doc;
  try {
    doc = loadYaml(src);
  } catch (e) {
    throw StateError('$file: تعذّر تحليلُ YAML — $e');
  }
  final out = <ShellBody>[];
  final root = doc is Map ? doc[gh ? 'jobs' : 'workflows'] : null;
  if (root is! Map) return out;
  for (final ge in root.entries) {
    final g = ge.value;
    if (g is! Map) continue;
    final steps = g[gh ? 'steps' : 'scripts'];
    if (steps is! List) continue;
    for (var i = 0; i < steps.length; i++) {
      final st = steps[i];
      if (st is! Map) continue;
      final name = (st['name'] ?? '<خطوة ${i + 1}>').toString();
      final text = st[gh ? 'run' : 'script'] is String
          ? st[gh ? 'run' : 'script'] as String
          : '';
      final extra = <String>[];
      if (gh && st['uses'] is String &&
          (st['uses'] as String).startsWith('./')) {
        extra.add(readLocalAction(file, name, st['uses'] as String));
      }
      if (text.isEmpty && extra.isEmpty) continue;
      extra.addAll(followScripts(file, name, text));
      final aliases = <String, String>{};
      final envKeys = <String>{};
      for (final e in [g['env'], st['env']]) {
        if (e is! Map) continue;
        e.forEach((k, v) {
          envKeys.add('$k');
          for (final s in kReleaseSecrets.keys) {
            if ('$v'.contains('secrets.$s')) aliases['$k'] = s;
          }
        });
      }
      out.add(ShellBody(file, ge.key.toString(), name, text, aliases,
          _truthy(st[gh ? 'continue-on-error' : 'ignore_failure']), extra,
          envKeys));
    }
  }
  return out;
}

/// الأسماءُ التي تُصدِّرُها خطوةٌ إلى بقيّةِ وظيفتِها عبرَ `$GITHUB_ENV` —
/// إسنادٌ **بنطاقِ الوظيفةِ** بتعريفِ Actions، لا قراءةُ بيئةٍ مجهولة. ولا
/// تُنتجُ ثقباً: خطوةٌ تُصدّرُ سرّاً (`echo "X=$SECRET" >> …`) **تَذكرُ
/// اسمَ السرِّ** فتَلزمُها بوّابتُه بالقاعدةِ (أ).
Map<String, Set<String>> jobExports(List<ShellBody> bodies) {
  final out = <String, Set<String>>{};
  for (final b in bodies) {
    for (final ln in maskComments(b.all).split('\n')) {
      if (!ln.contains('GITHUB_ENV')) continue;
      for (final m in RegExp(r'([A-Z][A-Z0-9_]{3,})=').allMatches(ln)) {
        (out['${b.file}|${b.job}'] ??= <String>{}).add(m.group(1)!);
      }
    }
  }
  return out;
}

List<String> releaseFiles() => [
      'codemagic.yaml',
      ...Directory('.github/workflows')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((f) => f.endsWith('.yml') || f.endsWith('.yaml')),
    ]..sort();

List<ShellBody> allBodies() {
  final out = <ShellBody>[];
  for (final f in releaseFiles()) {
    out.addAll(bodiesOf(f, File(f).readAsStringSync(),
        gh: f.startsWith('.github/')));
  }
  return out;
}

/// الأسرارُ التي يَذكرُها الجسمُ، ولكلِّ سرٍّ رمزُه الأوّلُ وموضعُه.
/// الرمزُ هو اسمُ السرِّ نفسُه أو اسمٌ محلّيٌّ مربوطٌ به في `env:` — فبوّابةٌ
/// على الاسمِ المحلّيِّ بوّابةٌ حقيقيّةٌ (وهي صيغةُ ستِّ خطواتٍ قائمةٍ في
/// المستودع: `SA_JSON`، `MAPBOX`، `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`).
Map<String, List<Object>> secretMentions(ShellBody b) {
  final s = maskComments(b.all);
  final res = <String, List<Object>>{};
  void note(String secret, String tok) {
    final at = RegExp(r'(?<![A-Za-z0-9_])' + RegExp.escape(tok) +
            r'(?![A-Za-z0-9_])')
        .firstMatch(s)
        ?.start;
    if (at == null) return;
    final prev = res[secret];
    if (prev == null || (prev[1] as int) > at) res[secret] = [tok, at];
  }

  for (final secret in kReleaseSecrets.keys) {
    note(secret, secret);
  }
  b.aliases.forEach((local, secret) => note(secret, local));
  return res;
}

/// جسمٌ مُصطنَعٌ من سكربتٍ واحد — الكاشفُ شفرةٌ تُختبَرُ كالشفرة، وبعدَ
/// الإصلاحِ يَصيرُ المصدرُ نظيفاً فنجاحُ المسحِ وحدَه لا يُبرهِنُ أنّه
/// يَرى شيئاً.
ShellBody synth(String script, {bool nonFatal = false}) {
  final ind = script
      .split('\n')
      .map((l) => l.isEmpty ? '' : '          $l')
      .join('\n');
  return bodiesOf(
      'synth.yaml',
      'workflows:\n  w:\n    scripts:\n      - name: s\n'
          '        ignore_failure: $nonFatal\n        script: |\n$ind\n',
      gh: false).single;
}

void main() {
  // ── (أ) القاعدةُ نفسُها ────────────────────────────────────────────────
  test('كلُّ سرٍّ يَذكرُه مسارُ إصدارٍ يُفحَصُ حضورُه قبلَ أوّلِ ذكرٍ له', () {
    final bad = <String>[];
    var mentions = 0;
    for (final b in allBodies()) {
      final ms = secretMentions(b);
      mentions += ms.length;
      for (final e in ms.entries) {
        final secret = e.key;
        final tok = e.value[0] as String;
        final at = e.value[1] as int;
        final key = '${b.file}|${b.step}|$secret';
        if (kUngatedAllowed.containsKey(key)) continue;
        final g = canonicalGate(maskComments(b.all), tok);
        if (g == null) {
          bad.add('$key: لا بوّابةَ قانونيّةً على «$tok»');
        } else if (at < g[0] || at > g[1]) {
          bad.add('$key: البوّابةُ **بعدَ** أوّلِ ذكرٍ لـ«$tok» — '
              'الاستعمالُ يَسبقُ الفحص');
        }
      }
    }
    expect(mentions, greaterThanOrEqualTo(30),
        reason: 'المسحُ انحلَّ: $mentions ذكرَ سرٍّ فقط — الحارسُ بلا موضوع');
    expect(bad, isEmpty,
        reason: 'سرٌّ يُستهلَكُ بلا فحصِ حضور — الغيابُ يُخرِجُ قيمةً فارغةً '
            'بخروجٍ صفر، فتَفشلُ الخطوةُ التاليةُ بلا سببٍ مقروء:\n'
            '  ${bad.join('\n  ')}');
  });

  // ── (ب) الاستثناءُ بسببٍ **وشاهدٍ مفحوص** ─────────────────────────────
  test('ومُستثنياتُ البوّابةِ مُعلَّلةٌ، وكلُّ دعوى منها مُتحقَّقةٌ', () {
    final bodies = allBodies();
    // لا مُدخَلَ ميْت: كلُّ مُستثنىً يَجبُ أن يُقابِلَ ذكرَ سرٍّ قائماً
    // **وغيرَ مُبوَّب** فعلاً — وإلّا كان الاستثناءُ بابَ إسكات.
    for (final key in kUngatedAllowed.keys) {
      final p = key.split('|');
      final b = bodies.firstWhere(
          (x) => x.file == p[0] && x.step == p[1],
          orElse: () => throw StateError('مُستثنىً لخطوةٍ لا وجودَ لها: $key'));
      final ms = secretMentions(b);
      expect(ms.containsKey(p[2]), isTrue,
          reason: '$key: الخطوةُ لم تَعُدْ تَذكرُ السرَّ — يُرفَعُ المُستثنى');
      final tok = ms[p[2]]![0] as String;
      expect(canonicalGate(maskComments(b.all), tok), isNull,
          reason: '$key: صارت له بوّابةٌ قانونيّةٌ — يُرفَعُ المُستثنى '
              'لا يُترَكُ يُجيزُ ما لم يَعُدْ يَحتاجُه');
    }

    // شاهدُ «تدهوُرٌ ظاهرٌ»: قاعدةُ إخفاءِ الزرِّ عند القيمةِ النائبةِ قائمة.
    final npc = File('lib/utils/native_pay_config.dart');
    expect(npc.existsSync(), isTrue,
        reason: 'زالت قاعدةُ القيمةِ النائبةِ — فغيابُ SAMSUNG_PAY_SERVICE_ID '
            'لم يَعُدْ تدهوُراً ظاهراً، ويُراجَعُ استثناؤه');
    expect(npc.readAsStringSync().contains('nativePayPlaceholder'), isTrue,
        reason: 'زال `nativePayPlaceholder` — شاهدُ الاستثناءِ ساقط');
    final sam = File('lib/screens/payment_summary_screen.dart')
        .readAsStringSync();
    expect(RegExp(r'nativePayPlaceholder\s*\(').hasMatch(sam), isTrue,
        reason: 'شاشةُ الدفعِ لم تَعُدْ تُنادي القاعدةَ — فالزرُّ يُعرَضُ على '
            'سرٍّ غائبٍ ولم يَبقَ للاستثناءِ سبب');

    // شاهدُ «أفضلُ جهد»: الخطوةُ غيرُ قاتلةٍ بإعلانِها، ومعها فرعُ تخطٍّ.
    final cancel = bodies.firstWhere((b) =>
        b.file == 'codemagic.yaml' &&
        b.step == 'Cancel existing App Store review submissions');
    expect(cancel.nonFatal, isTrue,
        reason: 'زالَ `ignore_failure` — صارت الخطوةُ قاتلةً، فيَلزمُها '
            'بوّابةٌ صارمةٌ ويُرفَعُ استثناؤها');
    expect(
        RegExp(r'if\s+not\s+ISSUER_ID\s+or\s+not\s+KEY_ID')
            .hasMatch(cancel.all),
        isTrue,
        reason: 'زالَ فرعُ التخطّي الصريحُ عند غيابِ السرّ — الاستثناءُ '
            'قائمٌ عليه');
  });

  // ── (ج) المجموعةُ المفتوحةُ تَفشلُ مُغلَقةً ───────────────────────────
  test('ولا اسمَ بيئةٍ كبيرٍ في مسارِ إصدارٍ خارجَ القائمتَين المثبَّتتَين',
      () {
    final unknown = <String, Set<String>>{};
    final bodies = allBodies();
    final exports = jobExports(bodies);
    for (final b in bodies) {
      final local = locallyAssigned(b.all);
      final exported = exports['${b.file}|${b.job}'] ?? const <String>{};
      for (final n in envNamesIn(b.all)) {
        if (kReleaseSecrets.containsKey(n)) continue;
        if (kNonSecretNames.containsKey(n)) continue;
        if (local.contains(n)) continue;
        if (exported.contains(n)) continue;
        if (b.envKeys.contains(n)) continue;
        (unknown['${b.file}|${b.step}'] ??= <String>{}).add(n);
      }
    }
    expect(unknown, isEmpty,
        reason: 'اسمٌ يُقرَأُ من البيئةِ ولا يُعرَفُ: أسِرٌّ هو فيَلزمُه '
            'بوّابةٌ، أم إعدادٌ فيُثبَّتُ في kNonSecretNames؟ '
            '(فسرٌّ جديدٌ يَدخلُ الفحصَ بنفسِه لا يَمُرُّ صامتاً)\n'
            '  ${unknown.entries.map((e) => "${e.key}: ${e.value.join(", ")}").join("\n  ")}');
  });

  test('وسرٌّ مثبَّتٌ لا يُعلَنُ متغيّرَ إعدادٍ عاديّاً في الملفّ', () {
    // الصيغةُ التي كانت تُسقِطُ اسماً من «السرّ» بمجرّدِ إعلانِه: سطرُ
    // `NAME: ""` في `vars:`. والمجموعةُ مثبَّتةٌ الآن فلا تُسقِطُه، لكنّ
    // إعلاناً كهذا يَعني سرّاً صارَ قيمةً مكشوفةً في المستودع.
    final declared = RegExp(r'^\s*([A-Z][A-Z0-9_]{3,}):\s*"', multiLine: true);
    final bad = <String>[];
    for (final f in releaseFiles()) {
      for (final m in declared.allMatches(File(f).readAsStringSync())) {
        if (kReleaseSecrets.containsKey(m.group(1))) {
          bad.add('$f: ${m.group(1)}');
        }
      }
    }
    expect(bad, isEmpty,
        reason: 'سرٌّ مُعلَنٌ قيمةً في الملفِّ: ${bad.join(", ")}');
  });

  // ── (د) أرضيّاتُ المسح ────────────────────────────────────────────────
  test('والمسحُ يَقرأُ مسارَ الإصدارِ كلَّه — لا انحلالَ أخضر', () {
    final files = releaseFiles();
    expect(files.length, greaterThanOrEqualTo(9),
        reason: 'مسحُ الملفّاتِ انحلَّ: ${files.length}');
    expect(files, contains('codemagic.yaml'));
    for (final f in Directory('.github/workflows').listSync().whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      expect(p.endsWith('.yml') || p.endsWith('.yaml'), isTrue,
          reason: 'امتدادٌ ثالثٌ يَتسلّلُ من المسح: $p');
    }
    final bodies = allBodies();
    expect(bodies.length, greaterThanOrEqualTo(40),
        reason: 'عَدُّ الأجسامِ انحلَّ: ${bodies.length} — '
            'تحليلُ YAML يُعيدُ فراغاً');
    // الخطوةُ التي من أجلِها وُجد الحارسُ، بعينِها.
    expect(
        bodies.any((b) =>
            b.file == 'codemagic.yaml' &&
            b.step == 'Write certificate private key'),
        isTrue,
        reason: 'خطوةُ مفتاحِ الشهادةِ خارجَ النظر');
  });

  // ── (د٢) القائمتانِ لا تُنقَلُ بينهما كلمة ───────────────────────────
  //
  // ثقبٌ وجدَته كتابةُ اختبارِ القضم: نقلُ اسمٍ من `kReleaseSecrets` إلى
  // `kNonSecretNames` يُسكِتُ فحصَه كلَّه — تَمُرُّ (أ) لأنّه لم يَعُدْ
  // سرّاً، وتَمُرُّ (ج) لأنّه صارَ «إعداداً»، ولا يَنقُصُ غيرُ رقمٍ في
  // أرضيّةٍ تَحتملُه. فالقائمتانِ مُتباينتانِ، والنصفُ الذي يُمكِنُ
  // اشتقاقُه **يُشتَقُّ**: كلُّ `${{ secrets.X }}` في سِيَرِ Actions سرٌّ
  // بالتعريفِ أيّاً كان ما تَقولُه القائمة.
  test('ولا اسمَ يُنقَلُ من «سرّ» إلى «إعداد» ليُسكَتَ فحصُه', () {
    for (final k in kReleaseSecrets.keys) {
      expect(kNonSecretNames.containsKey(k), isFalse,
          reason: '$k في القائمتَين — فالتباينُ هو ما يَمنعُ الإسكات');
    }
    // مُشتَقٌّ: ما يُعلِنُه Actions سرّاً لا يُمكِنُ أن يَصيرَ «إعداداً».
    final declaredSecrets = <String>{};
    for (final f in releaseFiles().where((f) => f.startsWith('.github/'))) {
      declaredSecrets.addAll(RegExp(r'secrets\.([A-Za-z0-9_]+)')
          .allMatches(File(f).readAsStringSync())
          .map((m) => m.group(1)!));
    }
    expect(declaredSecrets.length, greaterThanOrEqualTo(10),
        reason: 'اشتقاقُ أسرارِ Actions انحلَّ: ${declaredSecrets.length}');
    for (final k in declaredSecrets) {
      expect(kReleaseSecrets.containsKey(k), isTrue,
          reason: '$k يُعلِنُه السيرُ سرّاً وليس في kReleaseSecrets — '
              'فلا يُفحَصُ استعمالُه');
    }
    // وما لا يُعلِنُه ملفٌّ (أسرارُ مجموعاتِ Codemagic) مثبَّتٌ بالاسمِ:
    // لا سبيلَ إلى اشتقاقِه، فإسقاطُه يَجبُ أن يُحمِّر.
    for (final k in const [
      'CERTIFICATE_PRIVATE_KEY',
      'ANDROID_KEYSTORE_PASSWORD',
      'ANDROID_KEY_ALIAS',
      'GCLOUD_SERVICE_ACCOUNT_CREDENTIALS',
    ]) {
      expect(kReleaseSecrets.containsKey(k), isTrue,
          reason: '$k سرُّ مجموعةٍ في Codemagic لا يُعلِنُه الملفُّ — '
              'وإسقاطُه من القائمةِ يُسكِتُ فحصَه بلا أثر');
    }
  });

  // ── (هـ) الكاشفُ شفرةٌ تُختبَرُ كالشفرة ───────────────────────────────
  //
  // **تراجُعٌ عن إحدى وعشرينَ صيغةً مُثبَتة.** الصياغةُ السابقةُ سألت «أهذا
  // السطرُ كتابةُ ملفّ؟»، فكلُّ شكلٍ خارجَ تعدادِها كان يَمُرُّ **أخضرَ**
  // وهو يَكتبُ السرَّ كاملاً. والقاعدةُ الجديدةُ لا تَسألُ عن الكتابةِ
  // أصلاً، فالاثنتانِ والعشرونَ أدناه تُمسَكُ كلُّها بآليّةٍ واحدةٍ: الاسمُ
  // مذكورٌ. ولا يَكفي أن يَمُرَّ الفحصُ — يَجبُ أن يَراها واحدةً واحدةً،
  // وإلّا كان أخضرَ لأنّه لا يَقرأُ شيئاً.
  void mustFlag(String label, String script) {
    final b = synth(script);
    final ms = secretMentions(b);
    expect(ms.containsKey('CERTIFICATE_PRIVATE_KEY'), isTrue,
        reason: '$label: الكاشفُ لا يَرى ذِكرَ السرِّ — الصيغةُ تَمُرُّ خضراء');
    final tok = ms['CERTIFICATE_PRIVATE_KEY']![0] as String;
    expect(canonicalGate(maskComments(b.all), tok), isNull,
        reason: '$label: قُرئَ مُبوَّباً وهو بلا بوّابة');
  }

  test('ويَرى الصيغَ الاثنتَينِ والعشرينَ التي أعمَت الصياغةَ السابقةَ', () {
    const K = r'$CERTIFICATE_PRIVATE_KEY';
    final shapes = <String, String>{
      // توجيهٌ عاديٌّ — الصيغةُ الأصليّةُ للعطل.
      'توجيه': 'echo "$K" > /tmp/private.key',
      // أوامرُ إنشاءِ ملفٍّ خارجَ تعدادِ «أفعالِ الكتابة».
      'cp /dev/stdin': 'printf \'%s\\n\' "$K" | cp /dev/stdin /tmp/private.key',
      'openssl -out': 'printf \'%s\' "$K" | openssl enc -none -out /tmp/k',
      'git config --file': 'git config --file /tmp/k signing.key "$K"',
      'install /dev/stdin': 'printf \'%s\' "$K" | install -m600 /dev/stdin /tmp/k',
      'tee': 'printf \'%s\' "$K" | tee /tmp/k',
      'dd of=': 'printf \'%s\' "$K" | dd of=/tmp/k',
      // مُحرِّراتٌ في الموضعِ — لا توجيهَ فيها إطلاقاً.
      'sed -i': 'printf \'X\\n\' > /tmp/k\nsed -i "s|X|$K|" /tmp/k',
      'perl -pi': 'printf \'X\\n\' > /tmp/k\n'
          'perl -pi -e \'s/X/\$ENV{CERTIFICATE_PRIVATE_KEY}/\' /tmp/k',
      // توجيهٌ يَتجاوزُ سطرَه: الكاشفُ السطريُّ أعمى عنهما.
      'exec > f': 'exec 3>&1 > /tmp/k\necho "$K"\nexec 1>&3 3>&-',
      'exec 3> f': 'exec 3> /tmp/k\necho "$K" >&3\nexec 3>&-',
      // قراءةُ البيئةِ بتهجئاتٍ لا `\$` فيها.
      'printenv': 'printenv CERTIFICATE_PRIVATE_KEY > /tmp/k',
      'jq \$ENV': 'jq -nr \'\$ENV.CERTIFICATE_PRIVATE_KEY\' > /tmp/k',
      'python environ[]':
          'python3 -c \'import os;open("/tmp/k","w")'
              '.write(os.environ["CERTIFICATE_PRIVATE_KEY"])\'',
      'python environ.get':
          'python3 -c \'import os;open("/tmp/k","w")'
              '.write(os.environ.get("CERTIFICATE_PRIVATE_KEY",""))\'',
      'node process.env':
          'node -e \'require("fs").appendFileSync("/tmp/k",'
              'process.env.CERTIFICATE_PRIVATE_KEY||"")\'',
      'perl \$ENV{}':
          'perl -e \'open(F,">","/tmp/k");print F \$ENV{CERTIFICATE_PRIVATE_KEY}\'',
      'ruby ENV[]':
          'ruby -e \'File.write("/tmp/k", ENV["CERTIFICATE_PRIVATE_KEY"])\'',
      // heredoc إلى أمرٍ ليس «كتابةً» — فجسمُه لم يُفحَصْ قطّ.
      'heredoc → cp': 'cat << PEM | cp /dev/stdin /tmp/k\n$K\nPEM',
      // **صيغةُ المستودعِ نفسِه** (codemagic.yaml:73) — أخطرُ ما وُجد.
      'python3 - <<PY': 'python3 - <<\'PY\'\nimport os\n'
          'open("/tmp/k","w").write(os.environ["CERTIFICATE_PRIVATE_KEY"])\nPY',
      // كتلةٌ قوسيّةٌ تَحجبُ ما فيها.
      'brace group': '{ printf \'%s\' "$K"; } > /tmp/k',
      // قيمةٌ تُمرَّرُ وسيطَ أمرٍ لا كتابةَ ملفٍّ أصلاً — والغيابُ يُفشِلُ
      // الأمرَ بخطأٍ لا يُسمّي سرّاً، وهو ما تَعمى عنه أيُّ قاعدةٍ تَشترطُ
      // كتابةَ ملفّ.
      'وسيطُ أمر': 'app-store-connect do-thing --key "$K"',
    };
    expect(shapes.length, greaterThanOrEqualTo(22));
    shapes.forEach(mustFlag);
  });

  test('ولا يَرى ما ليس ذِكرَ سرٍّ — فالقاعدةُ ليست «أيُّ اسمٍ كبير»', () {
    for (final ok in <String>[
      'echo "لا سرَّ هنا" > /tmp/k',
      'printf \'%s\' "\$RUNNER_TEMP" > /tmp/k',
    ]) {
      final b = synth(ok);
      expect(secretMentions(b).containsKey('CERTIFICATE_PRIVATE_KEY'), isFalse,
          reason: 'إيجابيّةٌ كاذبةٌ على: $ok');
    }
    // واسمُ سرٍّ في نصٍّ مُقتبَسٍ **يُعَدُّ ذِكراً** ويُحمِّر: الجهةُ
    // الصحيحةُ للمجموعةِ المفتوحةِ. فالفحصُ قد يُحمِّرُ على ذِكرٍ نثريٍّ
    // لا يَقرأُ البيئةَ — وذاك مُراجَعةٌ لا ثقب، بخلافِ العكس.
    expect(
        secretMentions(synth('echo "راجِعْ CERTIFICATE_PRIVATE_KEY" > /tmp/k'))
            .containsKey('CERTIFICATE_PRIVATE_KEY'),
        isTrue,
        reason: 'ذِكرٌ نثريٌّ قُرئَ لا شيء — والقاعدةُ تَفشلُ مُغلَقةً عمداً');
  });

  // ── (و) البوّابةُ: ما يُقبَلُ وما **ليس بوّابةً** ──────────────────────
  test('والبوّابةُ تُقبَلُ بأشكالِها الثلاثةِ وحدَها', () {
    const K = 'CERTIFICATE_PRIVATE_KEY';
    for (final g in <String, String>{
      'شرطٌ مباشرٌ': 'if [ -z "\$$K" ]; then\n  echo "غائب" >&2\n  exit 1\nfi\n'
          'echo "\$$K" > /tmp/k',
      'بقوسَين معقوفَين': 'if [ -z "\${$K}" ]; then exit 1; fi\n'
          'echo "\${$K}" > /tmp/k',
      'test': 'if test -z "\$$K"; then exit 1; fi\necho "\$$K" > /tmp/k',
      'حلقةٌ على أسماء':
          'for v in FOO $K BAR; do\n  eval "val=\\\$\$v"\n'
              '  if [ -z "\$val" ]; then\n    echo "x" >&2\n    exit 1\n  fi\n'
              'done\necho "\$$K" > /tmp/k',
      'صيغةُ POSIX': ': "\${$K:?غائب}"\necho "\$$K" > /tmp/k',
    }.entries) {
      final b = synth(g.value);
      final ms = secretMentions(b);
      expect(ms.containsKey(K), isTrue, reason: '${g.key}: لم يُرَ السرُّ');
      final at = ms[K]![1] as int;
      final r = canonicalGate(maskComments(b.all), ms[K]![0] as String);
      expect(r, isNotNull, reason: '${g.key}: بوّابةٌ قانونيّةٌ قُرئت لا شيء');
      expect(at >= r![0] && at <= r[1], isTrue,
          reason: '${g.key}: أوّلُ ذكرٍ خارجَ نطاقِ البوّابة');
    }
  });

  test('وما ليس بوّابةً لا يُقرأُ بوّابةً — ستُّ صيغٍ مُثبَتةٌ كانت تَفوز', () {
    const K = 'CERTIFICATE_PRIVATE_KEY';
    final notGates = <String, String>{
      // الخروجُ يُنهي الصدفةَ الفرعيّةَ لا الخطوةَ — فالبناءُ يَمضي.
      'صدفةٌ فرعيّة': 'if [ -z "\$$K" ]; then ( exit 1 ); fi',
      // شرطٌ لا يَصدُقُ أبداً حولَ الخروج.
      'شرطٌ متداخلٌ كاذب':
          'if [ -z "\$$K" ]; then\n  if [ 1 -eq 2 ]; then exit 1; fi\nfi',
      // الخروجُ في الجهةِ الخاطئة.
      'خروجٌ في else':
          'if [ -z "\$$K" ]; then\n  echo warn\nelse\n  exit 1\nfi',
      // قُطبيّةٌ معكوسة: يَصدُقُ عند **حضورِ** السرّ.
      'قُطبيّةٌ معكوسة': 'if [ ! -z "\$$K" ]; then exit 1; fi',
      // تحذيرٌ بلا خروج — «فحصٌ» يُطبَعُ ثمّ يَمضي البناء.
      'تحذيرٌ بلا خروج': 'if [ -z "\$$K" ]; then echo "::warning::غائب"; fi',
      // خروجٌ بصفر: الخطوةُ تَنجحُ والبناءُ يَمضي بلا السرّ.
      'exit 0': 'if [ -z "\$$K" ]; then echo x; exit 0; fi',
    };
    expect(notGates.length, greaterThanOrEqualTo(6));
    notGates.forEach((label, body) {
      expect(canonicalGate(maskComments(synth(body).all), K), isNull,
          reason: '$label: قُرئَ بوّابةً — الصيغةُ أثبتت أنّها لا تُفشِلُ البناء');
    });
  });

  test('والبوّابةُ **بعدَ** الاستعمالِ لا تُنجّي: الترتيبُ هو الفحص', () {
    const K = 'CERTIFICATE_PRIVATE_KEY';
    final b = synth('echo "\$$K" > /tmp/k\n'
        'if [ -z "\$$K" ]; then\n  echo x >&2\n  exit 1\nfi');
    final ms = secretMentions(b);
    final at = ms[K]![1] as int;
    final g = canonicalGate(maskComments(b.all), K);
    expect(g, isNotNull, reason: 'البوّابةُ نفسُها غيرُ مقروءة');
    expect(at < g![0], isTrue,
        reason: 'أوّلُ ذكرٍ قُرئَ داخلَ البوّابةِ وهو قبلَها — '
            'فالكتابةُ تَسبقُ الفحصَ وتَمُرّ');
  });

  test('وتجريدُ المُقتبَسِ حاملٌ: قوسٌ في رسالةٍ ليس صدفةً فرعيّة', () {
    const K = 'CERTIFICATE_PRIVATE_KEY';
    final b = synth('if [ -z "\$$K" ]; then\n'
        '  echo "السرُّ غائبٌ (راجِعْ المجموعة)" >&2\n  exit 1\nfi');
    expect(canonicalGate(maskComments(b.all), K), isNotNull,
        reason: 'قوسٌ داخلَ نصٍّ مُقتبَسٍ أسقطَ بوّابةً صحيحة');
    expect(blankQuoted('a "b(c)" d').contains('('), isFalse,
        reason: 'التجريدُ لا يَحجبُ محتوى المُقتبَس');
    expect(blankQuoted('a (b) c').contains('('), isTrue,
        reason: 'التجريدُ يَحجبُ قوساً حقيقيّاً — فالفحصُ البنيويُّ بلا موضوع');
  });

  // ── (ز) بِنيةُ الـYAML: ثلاثُ صيغٍ كانت تُنتجُ «صفرَ خطوات» ───────────
  test('وبِنيةُ الـYAML لا تُخفي خطوةً — تحليلٌ حقيقيٌّ لا عَدُّ أسطر', () {
    const w = 'echo "\$CERTIFICATE_PRIVATE_KEY" > /tmp/k';
    final variants = <String, String>{
      // مَسرَدٌ بإزاحةِ صفرٍ تحتَ `steps:` — صيغةٌ اصطلاحيّةٌ تماماً.
      'مَسرَدٌ بإزاحةِ صفر':
          'jobs:\n  j:\n    steps:\n    - name: s\n      run: $w\n',
      // رمزٌ زائدٌ على سطرِ المفتاح.
      'تعليقٌ على سطرِ المفتاح':
          'jobs:\n  j:\n    steps: # خطوات\n      - name: s\n        run: $w\n',
      // مِرساةٌ مُعرَّفةٌ **خارجَ** الخطوات.
      'مِرساةُ YAML':
          'x: &a\n  - name: s\n    run: $w\njobs:\n  j:\n    steps: *a\n',
      // مَسرَدٌ تدفّقيّ.
      'مَسرَدٌ تدفّقيّ':
          'jobs:\n  j:\n    steps: [{name: s, run: \'$w\'}]\n',
    };
    variants.forEach((label, src) {
      final bodies = bodiesOf('v.yml', src, gh: true);
      expect(bodies.length, 1, reason: '$label: الخطوةُ خارجَ النظر');
      expect(
          secretMentions(bodies.single)
              .containsKey('CERTIFICATE_PRIVATE_KEY'),
          isTrue,
          reason: '$label: السرُّ غيرُ مرئيّ');
    });
  });

  test('وخطوةٌ بلا `name:` تَبقى مرئيّةً ومُسمّاةً بموضعِها', () {
    final b = bodiesOf('v.yml',
        'jobs:\n  j:\n    steps:\n      - run: echo "\$CERTIFICATE_PRIVATE_KEY" > /tmp/k\n',
        gh: true).single;
    expect(b.step, contains('1'));
    expect(secretMentions(b).containsKey('CERTIFICATE_PRIVATE_KEY'), isTrue);
  });

  // ── (ح) كلُّ تعذُّرٍ يُحمِّر — لا تخطٍّ صامت ───────────────────────────
  test('وتعذُّرُ التحليلِ أو الإحالةِ يَرمي، لا يُعيدُ «صفرَ خطوات»', () {
    expect(() => bodiesOf('bad.yml', 'jobs: [1, 2\n', gh: true),
        throwsA(isA<StateError>()),
        reason: 'YAML غيرُ قانونيٍّ قُرئَ «صفرَ خطواتٍ» أي أخضر');
    expect(
        () => bodiesOf(
            'v.yml',
            'jobs:\n  j:\n    steps:\n      - name: s\n'
                '        run: bash .github/scripts/no_such_file_xyz.sh\n',
            gh: true),
        throwsA(isA<StateError>()),
        reason: 'سكربتٌ لا يُقرَأُ تُخطّيَ بصمت — فالكتابةُ فيه خارجَ النظر');
    expect(
        () => bodiesOf(
            'v.yml',
            'jobs:\n  j:\n    steps:\n      - name: s\n'
                '        uses: ./.github/actions/no_such_action_xyz\n',
            gh: true),
        throwsA(isA<StateError>()),
        reason: 'إجراءٌ محلّيٌّ لا يُقرَأُ تُخطّيَ بصمت');
  });

  test('والإحالةُ تُتبَعُ فعلاً: سرٌّ داخلَ سكربتٍ مُنادًى يُرى', () {
    final d = Directory('.dart_tool/relsec_t')..createSync(recursive: true);
    final f = File('${d.path}/w.sh')
      ..writeAsStringSync('echo "\$CERTIFICATE_PRIVATE_KEY" > /tmp/k\n');
    addTearDown(() => d.deleteSync(recursive: true));
    final b = bodiesOf('v.yml',
        'jobs:\n  j:\n    steps:\n      - name: s\n        run: bash ${f.path}\n',
        gh: true).single;
    expect(b.extra, isNotEmpty, reason: 'لم يُقرَأْ السكربتُ المُنادى');
    expect(secretMentions(b).containsKey('CERTIFICATE_PRIVATE_KEY'), isTrue,
        reason: 'سرٌّ في سكربتٍ مُنادًى غيرُ مرئيّ — ثقبُ الإحالة');
  });

  // ── (ط) الاسمُ المحلّيُّ المربوطُ بسرّ ────────────────────────────────
  test('وبوّابةٌ على اسمٍ محلّيٍّ مربوطٍ بسرٍّ بوّابةٌ حقيقيّة', () {
    final b = bodiesOf(
        'v.yml',
        'jobs:\n  j:\n    steps:\n      - name: s\n        env:\n'
            '          SA: \${{ secrets.FIREBASE_SERVICE_ACCOUNT }}\n'
            '        run: |\n'
            '          if [ -z "\$SA" ]; then\n            exit 1\n          fi\n'
            '          printf \'%s\' "\$SA" > /tmp/sa.json\n',
        gh: true).single;
    final ms = secretMentions(b);
    expect(ms.containsKey('FIREBASE_SERVICE_ACCOUNT'), isTrue,
        reason: 'الربطُ في `env:` لم يُقرَأْ ذِكراً للسرّ');
    expect(ms['FIREBASE_SERVICE_ACCOUNT']![0], 'SA');
    final at = ms['FIREBASE_SERVICE_ACCOUNT']![1] as int;
    final g = canonicalGate(maskComments(b.all), 'SA');
    expect(g, isNotNull);
    expect(at >= g![0] && at <= g[1], isTrue);
  });

  test('ولا يُنجّي الربطُ من البوّابة: اسمٌ مربوطٌ بلا فحصٍ يُحمِّر', () {
    final b = bodiesOf(
        'v.yml',
        'jobs:\n  j:\n    steps:\n      - name: s\n        env:\n'
            '          SA: \${{ secrets.FIREBASE_SERVICE_ACCOUNT }}\n'
            '        run: printf \'%s\' "\$SA" > /tmp/sa.json\n',
        gh: true).single;
    final ms = secretMentions(b);
    expect(ms.containsKey('FIREBASE_SERVICE_ACCOUNT'), isTrue);
    expect(canonicalGate(maskComments(b.all), ms['FIREBASE_SERVICE_ACCOUNT']![0] as String),
        isNull,
        reason: 'ربطٌ في `env:` قُرئَ فحصاً — وهو إسنادٌ لا فحص');
  });
}
