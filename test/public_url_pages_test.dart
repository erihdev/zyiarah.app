// حارسُ **كلِّ رابطٍ نَنشرُه على `zyiarah.com`**: لا مسارَ بلا صفحة.
//
// ═══ لماذا ═══
//
// `firebase.json` يَخدمُ هدفَ `web` من `landing_page` بـ`cleanUrls: true`
// و**بلا أيِّ `rewrites`** — فالمسارُ `/x` يُحَلُّ إلى `landing_page/x.html`
// حصراً، وغيابُ الملفِّ هو **404**: صفحةُ Firebase الإنجليزيّةُ «Page Not
// Found» على نطاقٍ عربيٍّ بالكامل. ولم يَكن أحدٌ يَقرأُ ذلك، فمسحٌ لكلِّ
// `https://zyiarah.com/...` في المستودعِ وجدَ **أربعةَ مساراتٍ من ستّةٍ بلا
// ملفّ**، وكلُّها تُسلَّمُ إلى نظامٍ خارجيٍّ لا إلى زائرٍ عابر:
//
//   • `/payment-success`, `/payment-failure`, `/payment-cancel` —
//     `merchant_url` الذي يُسلّمُه `createTamaraCheckout` لتمارا، أي ما
//     تُحوِّلُ إليه بوّابةُ التقسيطِ المتصفّحَ لحظةَ انتهاءِ الدفع. والشاشاتُ
//     تَعترِضُه في `onPageStarted` — أي **بعدَ بدءِ التحميلِ** — ومسارُ النجاحِ
//     يَنتظرُ قراءاتِ Firestore قبل أن يُغادر، فالـ404 يُرسَمُ في تلك النافذةِ
//     داخلَ شاشةٍ عنوانُها «إتمام الدفع - تمارا»: في اللحظةِ التي تَسألُ فيها
//     العميلةُ «هل وصلَ مالي؟».
//   • `/contracts` — متغيّرُ `actionUrl` في قالبِ `contract-approved` الذي
//     يُرسَلُ لها لحظةَ اعتمادِ عقدِها. (والوصولُ مشروطٌ بوجودِ القالبِ في
//     Resend: الاحتياطيُّ `_buildTemplateFallbackHtml` يُرشِّحُ مفاتيحَ
//     `url|link` فلا يَعرضُ الزرَّ — وذاك ما لا يُقرأُ من المستودع.)
//   • `/support` — افتراضُ `support_url` في اللوحة، وزرُّ «الدعم» أعلى
//     صفحةِ الإعداداتِ يَفتحُه؛ وهو كذلك الحقلُ **الإلزاميُّ** في المتجرَين
//     (Support URL في App Store Connect)، و404 هناك سؤالُ مراجعةٍ يُعطّلُ
//     الإصدارَ كما كانت صفحةُ الخصوصيّةِ تَفعل.
//
// فالقاعدةُ **مُشتَقّةٌ لا مكتوبة**: كلُّ `https://zyiarah.com/<path>` في
// المصدرِ يَجبُ أن يُحَلَّ إلى ملفٍّ مَخدومٍ — ورابطٌ خامسٌ يَدخلُ النطاقَ
// بنفسِه بدلَ أن يُنشَرَ بلا صفحة. ومعه `404.html` شبكةً عامّةً للمسارِ
// المُخطَأِ الذي لا يُحصى (تَخدمُه Firebase تلقائيّاً بهذا الاسم).
//
// وصفحاتُ الدفعِ **ثابتةٌ لحظيّةٌ** عن قصد: بلا JavaScript ولا صورٍ ولا أيِّ
// طلبٍ خارجيّ، لأنّها تُرسَمُ في نافذةٍ يَتركُها التطبيقُ مفتوحةً ثوانيَ.
// و**لا رابطَ فيها يُعيدُ الدفع**: جلسةُ تمارا ثانيةٌ على طلبٍ مدفوعٍ خصمٌ
// مكرَّرٌ استردادُه يدويّ — فالفحصُ يُثبّتُ أنّ مجموعةَ روابطِها لا تَزيدُ على
// الدعمِ والبريد. ولا بياناتَ تواصلٍ مُختَرَعة: البريدُ هو ما يَنشرُه
// `index.html` أصلاً، ولا رقمَ هاتفٍ (الأرقامُ الحقيقيّةُ في
// `system_configs/main_settings` خلفَ مصادقة، والافتراضاتُ في المُحرِّرِ
// عناصرُ تعبئةٍ `966500000000`).
//
// ولا Firestore في أيٍّ منها: إضافةُ قارئٍ لمستندٍ لا كاتبَ له هي بعينِها
// العطلُ المُصلَحُ في بياناتِ البائعِ على الفاتورة — و`privacy.html` وحدَها
// تَقرأُ المنشورَ (وبنصٍّ ثابتٍ احتياطيّاً)، فهي الاستثناءُ المُسمّى الذي
// يُثبِتُ أنّ الكاشفَ يَعضّ.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _dir = 'landing_page';
const String _fnIndex = 'functions/index.js';

/// جذورُ المسحِ: ما يُنشِئُه الإنسانُ، لا ما يُخرِجُه البناء.
const List<String> _scanRoots = [
  'lib',
  'functions',
  'admin_panel/src',
  'landing_page',
  'android',
  'ios',
  '.github',
];

const List<String> _scanExt = [
  '.dart', '.ts', '.tsx', '.js', '.html', '.json',
  '.yaml', '.yml', '.xml', '.plist', '.md',
];

bool _skipped(String path) {
  final parts = path.split(Platform.pathSeparator);
  return parts.contains('node_modules') ||
      parts.contains('dist') ||
      parts.contains('build') ||
      parts.contains('.dart_tool');
}

/// يَحجبُ التعليقاتِ **بالحالةِ** لا بالبادئة: تعليقُ `<!-- … -->` يَمتدُّ
/// أسطُراً وأسطُرُه التاليةُ نصٌّ عارٍ، و`//` في JS/Dart سطريّ. والحجبُ
/// بمسافاتٍ كي تَبقى الإزاحاتُ على حالها.
String _stripComments(String src) {
  String out = src.replaceAllMapped(
      RegExp(r'<!--[\s\S]*?-->'), (m) => ' ' * m.group(0)!.length);
  out = out.replaceAllMapped(
      RegExp(r'/\*[\s\S]*?\*/'), (m) => ' ' * m.group(0)!.length);
  return out
      .split('\n')
      .map((line) {
        final t = line.trimLeft();
        if (t.startsWith('//')) return ' ' * line.length;
        if (t.startsWith('#') && !t.startsWith('#!')) return ' ' * line.length;
        return line;
      })
      .join('\n');
}

/// ما يَخدمُه هدفُ `web` للمسارِ `/p` تحتَ `cleanUrls`.
String? _servedFileFor(String path) {
  if (path == '/') return '$_dir/index.html';
  final p = path.substring(1);
  for (final c in ['$_dir/$p.html', '$_dir/$p/index.html', '$_dir/$p']) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

/// كتلةٌ متوازنةُ الأقواسِ بدءاً من `open` بعدَ `anchor` — لا `indexOf('}')`،
/// فأوّلُ محرفٍ مطابقٍ فخٌّ أوقعَ أربعةَ حُرّاسٍ في هذا المستودع.
String _balanced(String src, String anchor, String open, String close) {
  final i = src.indexOf(anchor);
  if (i < 0) return '';
  final s = src.indexOf(open, i);
  if (s < 0) return '';
  int depth = 0;
  for (int j = s; j < src.length; j++) {
    if (src[j] == open) depth++;
    if (src[j] == close) {
      depth--;
      if (depth == 0) return src.substring(s, j + 1);
    }
  }
  return '';
}

Set<String> _hrefs(String html) => RegExp(r'href="([^"]+)"')
    .allMatches(_stripComments(html))
    .map((m) => m.group(1)!)
    .toSet();

void main() {
  final Map<String, Object?> fb =
      jsonDecode(File('firebase.json').readAsStringSync())
          as Map<String, Object?>;
  final web = (fb['hosting'] as List)
      .cast<Map<String, Object?>>()
      .firstWhere((h) => h['target'] == 'web');

  // ١) فرضيّةُ الحارسِ كلِّه — فلو زالت تُراجَعُ القاعدةُ لا تُسكَت.
  test('هدفُ web: landing_page بـcleanUrls وبلا rewrites', () {
    expect(web['public'], _dir,
        reason: 'جذرُ الهدفِ تغيّر — فمسارُ كلِّ صفحةٍ في هذا الفحصِ خاطئ');
    expect(web['cleanUrls'], isTrue,
        reason: 'بلا cleanUrls يَصيرُ `/support` 404 وإن وُجد support.html');
    expect(web.containsKey('rewrites'), isFalse,
        reason: 'أُضيفَ rewrite إلى هدفِ web — فالمسارُ لم يَعُد يُحَلُّ إلى '
            'ملفٍّ باسمِه، وهذا الحارسُ يَحتاجُ مراجعةً لا مرورَ صمت');
  });

  // ٢) القاعدةُ المُشتَقّة: كلُّ رابطٍ نُسلّمُه الخارجَ له صفحة.
  final Map<String, Set<String>> published = {};
  for (final root in _scanRoots) {
    final d = Directory(root);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (_skipped(f.path)) continue;
      if (!_scanExt.any((e) => f.path.endsWith(e))) continue;
      String src;
      try {
        src = f.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      for (final m in RegExp(r'https?://(?:www\.)?zyiarah\.com(/[A-Za-z0-9_\-/]*)?')
          .allMatches(_stripComments(src))) {
        var p = m.group(1) ?? '/';
        if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
        if (p.isEmpty) p = '/';
        published.putIfAbsent(p, () => <String>{}).add(f.path);
      }
    }
  }

  test('كلُّ مسارِ zyiarah.com يَنشرُه المستودعُ له صفحةٌ مَخدومة', () {
    expect(published.length, greaterThanOrEqualTo(6),
        reason: 'المسحُ انهارَ (${published.length} مسار) — حارسٌ لا يَجدُ '
            'شيئاً أسوأُ من لا حارس');
    final sources = published.values.expand((e) => e).toSet();
    expect(sources.length, greaterThanOrEqualTo(4),
        reason: 'المسحُ قرأَ ${sources.length} ملفّاً فقط — تَحقَّقْ من الجذور');

    final missing = <String, Set<String>>{};
    for (final entry in published.entries) {
      if (_servedFileFor(entry.key) == null) missing[entry.key] = entry.value;
    }
    expect(missing, isEmpty,
        reason: 'مساراتٌ تُنشَرُ بلا صفحةٍ ⇒ 404 إنجليزيٌّ عند مَن فتحَها: '
            '$missing');
  });

  // ٣) وداخلُ الموقعِ كذلك: رابطٌ نسبيٌّ إلى صفحةٍ غائبةٍ 404 أيضاً.
  test('كلُّ رابطٍ نسبيٍّ في صفحاتِ الموقعِ يُحَلُّ إلى ملفّ', () {
    final pages = Directory(_dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.html'))
        .toList();
    expect(pages.length, greaterThanOrEqualTo(7),
        reason: 'صفحاتُ الموقعِ ${pages.length} — المسحُ لم يَقرأ');
    int links = 0;
    final broken = <String>[];
    for (final f in pages) {
      for (final h in _hrefs(f.readAsStringSync())) {
        if (!h.startsWith('/')) continue;
        final p = h.split('#').first.split('?').first;
        links++;
        if (_servedFileFor(p.endsWith('/') && p.length > 1
                ? p.substring(0, p.length - 1)
                : p) ==
            null) {
          broken.add('${f.path} → $h');
        }
      }
    }
    expect(links, greaterThanOrEqualTo(8),
        reason: 'لم يُقرأ إلّا $links رابطاً — الاقتطاعُ أخطأ');
    expect(broken, isEmpty, reason: 'روابطُ داخليّةٌ مكسورة: $broken');
  });

  // ٤) الطرفانِ مشدودانِ معاً: ما نُسلّمُه تمارا == الصفحاتُ الموجودة.
  test('merchant_url الذي يُسلَّمُ تمارا هو الصفحاتُ الثلاثُ بعينِها', () {
    final block = _balanced(
        _stripComments(File(_fnIndex).readAsStringSync()),
        'merchant_url',
        '{',
        '}');
    expect(block, isNotEmpty,
        reason: 'لم يُقتطَع merchant_url — الاقتطاعُ أخطأ أو الكتلةُ زالت');
    final paths = RegExp(r'zyiarah\.com(/[A-Za-z0-9_\-]+)')
        .allMatches(block)
        .map((m) => m.group(1)!)
        .toSet();
    expect(paths, {'/payment-success', '/payment-failure', '/payment-cancel'},
        reason: 'تغيّرت مساراتُ العَوْدةِ المُسلَّمةُ لتمارا — فالصفحاتُ '
            'المنشورةُ لم تَعُد هي ما يُفتَح');
    for (final p in paths) {
      expect(_servedFileFor(p), isNotNull, reason: '$p بلا صفحة');
    }
  });

  // ٥) واعتراضُ التطبيقِ على الأسماءِ نفسِها — تسميةٌ تَنفردُ تَكسِرُ الاعتراض.
  test('اعتراضُ الشاشاتِ يُطابِقُ أسماءَ الصفحاتِ المنشورة', () {
    const screens = [
      'lib/screens/checkout_screen.dart',
      'lib/screens/store_payment_screen.dart',
    ];
    final seen = <String>{};
    for (final s in screens) {
      final src = _stripComments(File(s).readAsStringSync());
      for (final m
          in RegExp(r"'(payment-[a-z]+)'").allMatches(src)) {
        seen.add('/${m.group(1)!}');
      }
    }
    expect(seen, {'/payment-success', '/payment-failure', '/payment-cancel'},
        reason: 'اعتراضُ الشاشاتِ انفردَ عن الصفحاتِ المنشورة: $seen');
  });

  // ٦) صفحاتُ الدفعِ لحظيّة: تُرسَمُ في نافذةٍ يَتركُها التطبيقُ مفتوحةً ثوانيَ.
  test('صفحاتُ الدفعِ بلا JavaScript ولا صورٍ ولا طلبٍ خارجيّ', () {
    for (final name in const [
      'payment-success',
      'payment-failure',
      'payment-cancel',
    ]) {
      final body = _stripComments(File('$_dir/$name.html').readAsStringSync());
      for (final bad in const ['<script', '<img', 'src=', '@import', 'https://']) {
        expect(body.contains(bad), isFalse,
            reason: '$name.html يَحملُ «$bad» — فلن تُرسَمَ من أوّلِ بايت');
      }
      expect(body.contains('noindex'), isTrue,
          reason: '$name.html هدفُ تحويلٍ آليٌّ لا محتوىً — يَلزمُه noindex');
    }
  });

  // ٧) ولا رابطَ فيها يُعيدُ الدفع — خصمٌ مكرَّرٌ استردادُه يدويّ.
  test('روابطُ صفحاتِ الدفعِ لا تَزيدُ على الدعمِ والبريد', () {
    for (final name in const [
      'payment-success',
      'payment-failure',
      'payment-cancel',
    ]) {
      final hs = _hrefs(File('$_dir/$name.html').readAsStringSync());
      expect(hs, {'mailto:support@zyiarah.com', '/support'},
          reason: '$name.html اكتسبَ رابطاً — ومسارُ دفعٍ ثانٍ من هذه الصفحةِ '
              'خصمٌ مكرَّر');
    }
  });

  // ٨) والنجاحُ لا يَدّعي تأكيدَ الطلبِ: الـwebhook هو مَن يَقلبُ is_paid.
  test('صفحةُ النجاحِ تَقولُ «نُؤكّدُ الآن» لا «تمَّ تأكيدُ طلبك»', () {
    final s = File('$_dir/payment-success.html').readAsStringSync();
    expect(s.contains('نُؤكّدُ طلبكِ الآن'), isTrue,
        reason: 'زالت جملةُ «قيدَ التأكيد» — فالصفحةُ تَدّعي ما لم يَحدُثْ بعد');
    expect(s.contains('لا تُعيدي الدفع'), isTrue,
        reason: 'زالَ النهيُ عن إعادةِ الدفعِ — وهو ما يَمنعُ خصماً مكرَّراً '
            'عند تأخّرِ التأكيد');
    for (final bad in const ['تم تأكيد طلبك', 'طلبكِ مؤكَّد', 'تم تفعيل']) {
      expect(s.contains(bad), isFalse,
          reason: 'ادّعاءٌ «$bad» لا تَملكُه الصفحة');
    }
  });

  // ٩) ولا بياناتَ تواصلٍ مُختَرَعة.
  test('صفحةُ الدعمِ تَنشرُ بريدَ الموقعِ نفسَه ولا رقمَ هاتف', () {
    Set<String> mails(String f) => _hrefs(File('$_dir/$f').readAsStringSync())
        .where((h) => h.startsWith('mailto:'))
        .toSet();
    expect(mails('support.html'), mails('index.html'),
        reason: 'بريدُ صفحةِ الدعمِ انفردَ عن المنشورِ في الصفحةِ الرئيسيّة');
    expect(mails('index.html'), isNotEmpty,
        reason: 'لم يُقرأ بريدٌ من index.html — الاقتطاعُ أخطأ');
    final body = _stripComments(File('$_dir/support.html').readAsStringSync());
    for (final re in [
      // `00?` كان يَشترطُ صفراً فلا يَرى «966…» العاريةَ — كشفَه اختبارُ القضم.
      RegExp(r'(\+|00)?966\s?\d'),
      RegExp(r'\b05\d{8}\b'),
      RegExp(r'\b9200\d{5}\b'),
      RegExp(r'\btel:'),
    ]) {
      expect(re.hasMatch(body), isFalse,
          reason: 'رقمُ هاتفٍ في صفحةِ الدعم — الأرقامُ الحقيقيّةُ في '
              'main_settings خلفَ مصادقة، وافتراضاتُ المُحرِّرِ عناصرُ تعبئة');
    }
  });

  // ١٠) ولا قارئَ Firestore في صفحةٍ يَجبُ أن تَعملَ دائماً.
  test('صفحاتُ الدعمِ والدفعِ والعقودِ و404 بلا Firebase SDK', () {
    for (final name in const [
      'support.html',
      'contracts.html',
      '404.html',
      'payment-success.html',
      'payment-failure.html',
      'payment-cancel.html',
    ]) {
      final body = _stripComments(File('$_dir/$name').readAsStringSync());
      for (final bad in const ['firebasejs', 'initializeApp', 'getFirestore']) {
        expect(body.contains(bad), isFalse,
            reason: '$name صارَ يَقرأُ Firestore — وقارئٌ لمستندٍ لا كاتبَ له '
                'هو العطلُ المُصلَحُ في بياناتِ البائع');
      }
    }
    // والاستثناءُ المُسمّى يُثبِتُ أنّ الكاشفَ يَعضّ.
    final priv = _stripComments(File('$_dir/privacy.html').readAsStringSync());
    expect(priv.contains('initializeApp'), isTrue,
        reason: 'privacy.html لم تَعُد تَقرأُ المنشور — الكاشفُ أعمى الآن');
  });

  // ١١) شبكةُ المسارِ المُخطَأِ الذي لا يُحصى.
  test('404.html موجودةٌ وعربيّةٌ وتُخرِجُ الزائرَ من الطريقِ المسدود', () {
    final f = File('$_dir/404.html');
    expect(f.existsSync(), isTrue,
        reason: 'بلاها تَخدمُ Firebase صفحةً إنجليزيّةً على نطاقٍ عربيّ');
    final s = f.readAsStringSync();
    expect(s.contains('dir="rtl"'), isTrue);
    expect(_hrefs(s).containsAll({'/', '/support'}), isTrue,
        reason: '404 بلا مَخرَجٍ طريقٌ مسدود');
  });

  // ١٢) وصفحةُ الدعمِ مربوطةٌ من الموقعِ — صفحةٌ لا يَصِلُها رابطٌ لا يَجدُها مُراجِع.
  test('الصفحةُ الرئيسيّةُ تَربطُ /support', () {
    expect(_hrefs(File('$_dir/index.html').readAsStringSync()),
        contains('/support'),
        reason: 'زالَ رابطُ الدعمِ من التذييل — ومُراجِعُ المتجرِ يَتنقّلُ من '
            'الصفحةِ الرئيسيّة');
  });

  // ١٣) والحجبُ لا يُجوِّفُ الفحص: المُصطلحاتُ مذكورةٌ في تعليقاتي هنا وهناك.
  test('حجبُ التعليقاتِ يَعملُ، والمُصطلحُ ما زال في الخامّ', () {
    final raw = File('$_dir/payment-success.html').readAsStringSync();
    expect(raw.contains('_tamaraFlipPaid'), isTrue,
        reason: 'زالَ تعليقُ السببِ من الصفحة');
    expect(_stripComments(raw).contains('_tamaraFlipPaid'), isFalse,
        reason: 'الحجبُ لا يَعملُ على تعليقِ HTML المتعدّدِ الأسطر — '
            'فالفحوصُ أعلاه تَقرأُ توثيقي لا شفرتي');
    final fn = File(_fnIndex).readAsStringSync();
    expect(fn.contains('zyiarah.com/payment-success'), isTrue,
        reason: 'زالَ الرابطُ من index.js — فالفحصُ (٤) بلا ما يَشدُّه');
  });
}
