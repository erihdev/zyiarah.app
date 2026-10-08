import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/phone_format.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **رقمُ الجوالِ السعوديُّ: صيغةٌ واحدة.**
///
/// كانت ثلاثُ شاشاتٍ تَكتبُ `users/{uid}.phone` بثلاثِ صِيَغَ وبلا فحصٍ
/// مشترَك، و`createTamaraCheckout` يُلحِقُ `+966` بالمخزَّنِ كما هو — فـ
/// `0501234567` تَبلغُ بوّابةَ التقسيطِ `+9660501234567`. التعليلُ كاملاً في
/// ترويسةِ `lib/utils/phone_format.dart`.
///
/// وجدولُ الحالاتِ **مشترَكٌ بين اللغتَين**: هذا الملفُّ يَملكُه و
/// `functions/test/phone.test.js` يَقرؤه حرفيّاً ويُقابِلُ أجوبتَه — فافتراقُ
/// جهةٍ يَسقطُ الفحص (نمطُ `ticket_authorship`/`serviceMeta`/`buildGate`).
///
/// SAUDI_MOBILE_CASES_BEGIN
const String _casesJson = '''
[
  ["محلّيٌّ بصفرٍ",            "0501234567",        "0501234567"],
  ["تسعةٌ عارية",              "501234567",         "0501234567"],
  ["مفتاحُ الدولةِ عارياً",     "966501234567",      "0501234567"],
  ["مفتاحٌ بزائد",             "+966501234567",     "0501234567"],
  ["دوليٌّ بصفرَين",           "00966501234567",    "0501234567"],
  ["مفتاحٌ ومحلّيٌّ بصفر",      "9660501234567",     "0501234567"],
  ["مسافاتٌ وشرطات",           "+966 50-123 4567",  "0501234567"],
  ["محلّيٌّ بمسافات",          "05 0123 4567",      "0501234567"],
  ["عربيٌّ-هنديّ",             "٠٥٠١٢٣٤٥٦٧",        "0501234567"],
  ["فارسيّ",                   "۰۵۰۱۲۳۴۵۶۷",        "0501234567"],
  ["علامةُ اتّجاهٍ لاصقة",      "\u202a+966 53 048 9016\u202c", "0530489016"],
  ["بادئةُ 055",               "0551234567",        "0551234567"],
  ["أرضيٌّ جازاني",            "0173171234",        null],
  ["دولةٌ أخرى",               "+971501234567",     null],
  ["النائبُ المعروف",          "000000000",         null],
  ["صفرانِ بلا مفتاح",         "00501234567",       null],
  ["أطولُ من تسعةٍ بعدَ ٥",     "5012345678",        null],
  ["فخُّ «آخرُ تسعة»",          "99999501234567",    null],
  ["غيرُ رقميّ",               "abc",               null],
  ["فارغ",                     "",                  null],
  ["مسافاتٌ فقط",              "   ",               null]
]
''';
/// SAUDI_MOBILE_CASES_END

List<List<dynamic>> _cases() => (jsonDecode(_casesJson) as List)
    .map((e) => (e as List).toList())
    .toList();

/// نطاقُ الكاتبِ/المُرسِلِ **مُشتَقٌّ**: كلُّ ملفٍّ في `lib/` يَضَعُ رقمَ جوالٍ
/// في حِملِ كتابةٍ أو في وسيطِ بوّابةِ دفع.
final RegExp _phoneSite = RegExp(
    r"""('phone'|'client_phone'|'user_phone'|"phone"|"client_phone"|"user_phone")\s*:|customerPhone\s*:""");

final RegExp _rule = RegExp(r'\b(saudiMobile|saudiE164|_canonicalPhone)\b');

/// قيمةُ المُدخَلِ بعدَ `'client_phone':` — حتى الفاصلةِ على **عمقِ صفر**
/// (موازنةٌ لا أوّلُ فاصلة: القيمةُ قد تكون `f(a, b)` أو ثلاثيّةً أو خريطة).
String _valueAfter(String code, int from) {
  var depth = 0;
  final out = StringBuffer();
  for (var i = from; i < code.length; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) break;
      depth--;
    }
    if ((c == ',' || c == ';') && depth == 0) break;
    out.write(c);
  }
  return out.toString().trim();
}

/// مُعرِّفٌ مفردٌ يُحَلُّ إلى **تعريفِه في الملفِّ نفسِه** — نمطٌ قائمٌ في
/// `money_format_test` و`booking_fields_test`: قائمةُ أسماءٍ مسموحةٍ تَتعفّن،
/// والحلُّ يَمنعُ `final x = raw; 'client_phone': x` كذلك.
String _resolve(String code, String value) {
  if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(value)) return value;
  final m = RegExp('(?:final|var|const)?\\s*(?:String\\??\\s+)?'
          '\\b$value\\s*=\\s*([^;]+);')
      .firstMatch(code);
  return m == null ? value : m.group(1)!.trim();
}

/// مَن يَضَعُ رقماً ولا يُنادي القاعدةَ — مع سببِ كلٍّ. الصِيَغُ لا تُعَدُّ
/// مخالفةً: **عرضٌ أو تسميةٌ أو موضوعٌ آخرُ (جوّالُ سائقٍ/موظّفٍ) أو تمريرٌ
/// للمخزَّنِ يُطبِّعُه الخادمُ.**
/// موضعٌ واحدٌ مُستثنًى **بموضعِه** لا بملفِّه: سجلُّ طلبِ حذفِ الحسابِ
/// يَكتبُ هاتفَ **المصادقةِ** (`account_deletions.phone`) لا جوّالَ العميلةِ
/// المخزَّن — والمصادقةُ بالبريدِ وحدَها فهو `null` **دائماً**، وهو مسجَّلٌ
/// كذلك في قرارِ `deletion_log_row` (الهويّةُ تُقرأُ `email ← name ← phone`).
/// فتطبيعُه لا يُغيّرُ شيئاً، ومجموعةٌ أخرى لها قُرّاؤها.
const Set<String> _siteExempt = {
  'lib/screens/profile_screen.dart|user?.phoneNumber',
};

const Map<String, String> _declaredExempt = {
  'lib/screens/admin/admin_audit_logs_screen.dart':
      'خريطةُ تسمياتٍ عربيّةٍ لحقولِ سجلِّ التدقيق — لا كتابة.',
  'lib/screens/admin/admin_drivers_screen.dart':
      'الأدمنُ يَكتبُ جوّالَ **سائق** — موضوعٌ آخر: لا تُرسَلُ إلى بوّابةِ '
          'دفعٍ ولا تُعبَّأُ منها شاشةُ العميلة، وقارئُها `whatsappNumber` '
          'المتسامحة.',
  'lib/screens/admin/admin_order_details_screen.dart':
      'تعبئةٌ رجعيّةٌ من مستندِ المستخدمِ ذاتِه، وخريطةُ عرضٍ في المُنتقي.',
  'lib/screens/admin/admin_staff_performance_screen.dart':
      'خريطةُ عرضٍ لبطاقةِ الأداء.',
  'lib/screens/checkout_screen.dart':
      'تمريرٌ لِما وصلَها (`widget.customerPhone`) — والخادمُ يُطبِّعُ قبلَ '
          'بادئةِ `+966`.',
  'lib/screens/orders_list_screen.dart':
      'تمريرُ `client_phone` المخزَّنِ إلى شاشةِ دفعِ المتجر — يُطبِّعُه '
          'الخادم.',
  'lib/screens/store_payment_screen.dart':
      'تمريرُ `widget.customerPhone` إلى النداءِ الخادميّ — يُطبِّعُه الخادم.',
  'lib/screens/store_screen.dart':
      'تمريرُ `client_phone` المخزَّنِ — يُطبِّعُه الخادم.',
  'lib/services/firebase_service.dart':
      'كاتبُ التسجيلِ ومسارُ توفيرِ الإدارة: الأوّلُ مُنادِيه **واحدٌ** '
          '(شاشةُ التسجيل) وهي تُطبِّعُ قبلَ النداء — مشدودٌ في (ج٢) — '
          'والثاني جوّالُ سائقٍ/موظّف.',
  'lib/services/store_service.dart':
      'يَقرأُ `users.phone` ويُمرّرُه إلى `store_orders`، وافتراضُه النائبُ '
          'المعروفُ `000000000` الذي تَعرفُه شاشةُ الدفعِ بعينِه — فتطبيعُه '
          'يُفقِدُ تلك الإشارة.',
};

void main() {
  // ───────── (أ) القاعدةُ سلوكاً، بأصنافٍ مُسمّاة ─────────
  group('(أ) القاعدةُ سلوكاً — جدولُ حالاتٍ بأصنافٍ مُسمّاة', () {
    for (final row in _cases()) {
      final label = row[0] as String;
      final input = row[1] as String;
      final want = row[2] as String?;
      test('$label: «$input» ⇒ ${want ?? 'مرفوض'}', () {
        expect(saudiMobile(input), want);
      });
    }

    test('أصنافٌ مُسمّاةٌ حاضرةٌ كلُّها — لا حدٌّ عدديٌّ وحدَه', () {
      // حدُّ الطولِ لا يَكشفُ ضياعَ صنف: الدرسُ المسجَّلُ في جدولِ الأرقامِ
      // العربيّة. فكلُّ صنفٍ مَقصودٍ يُسمّى.
      final labels = _cases().map((r) => r[0] as String).toSet();
      for (final must in const [
        'دوليٌّ بصفرَين', // العطلُ الحيُّ: كان يُرفَضُ في التسجيل
        'محلّيٌّ بصفرٍ', // ما يُنتجُ `+9660501234567`
        'مفتاحُ الدولةِ عارياً', // ما يُنتجُ `+966966501234567`
        'عربيٌّ-هنديّ',
        'فارسيّ',
        'علامةُ اتّجاهٍ لاصقة',
        'أرضيٌّ جازاني',
        'دولةٌ أخرى',
        'النائبُ المعروف',
        'فخُّ «آخرُ تسعة»',
      ]) {
        expect(labels, contains(must), reason: 'صنفٌ سقطَ من الجدول: $must');
      }
      expect(_cases().length, greaterThanOrEqualTo(20));
    });

    test('`null` مرفوضٌ ولا يَرمي', () {
      expect(saudiMobile(null), isNull);
      expect(saudiE164(null), isNull);
    });
  });

  // ───────── (ب) الدوليّةُ مُشتقَّةٌ من المحلّيّةِ لا مكتوبةٌ ثانيةً ─────────
  test('(ب) `saudiE164` مُشتقَّةٌ من `saudiMobile` في كلِّ حالة', () {
    for (final row in _cases()) {
      final input = row[1] as String;
      final local = saudiMobile(input);
      final e164 = saudiE164(input);
      if (local == null) {
        expect(e164, isNull, reason: 'مرفوضٌ محلّيّاً ومقبولٌ دوليّاً: «$input»');
      } else {
        expect(e164, '+966${local.substring(1)}',
            reason: 'الدوليّةُ لا تُطابِقُ المحلّيّةَ: «$input»');
        expect(RegExp(r'^\+9665\d{8}$').hasMatch(e164!), isTrue,
            reason: 'ليست E.164: «$input» ⇒ $e164');
      }
    }
  });

  // ───────── (ج) نطاقٌ مُشتَقٌّ: كلُّ كاتبٍ/مُرسِلٍ يُنادي القاعدة ─────────
  group('(ج) نطاقٌ مُشتَقٌّ — مجموعةُ مَن لا يُنادي القاعدةَ كاملةً', () {
    late final Map<String, int> sites;
    late final Set<String> silent;

    setUpAll(() {
      sites = <String, int>{};
      silent = <String>{};
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final raw = f.readAsStringSync();
        final n = _phoneSite.allMatches(stripComments(raw)).length;
        if (n == 0) continue;
        final rel = f.path.replaceAll(r'\', '/');
        sites[rel] = n;
        if (!_rule.hasMatch(raw)) silent.add(rel);
      }
    });

    test('(ج١) الاشتقاقُ أصابَ — أرضيّةٌ للمسح', () {
      expect(sites.length, greaterThanOrEqualTo(10),
          reason: 'انحلَّ مسحُ مواضعِ الجوال، فالمقارنةُ بلا موضوع');
      expect(sites['lib/screens/payment_summary_screen.dart'],
          greaterThanOrEqualTo(2),
          reason: 'شاشةُ الدفعِ هي المرجعُ الحقيقيُّ للمسح');
    });

    test('(ج٢) مجموعةُ الصامتِ = القائمةُ المُعلَنةُ بأسبابِها', () {
      expect(silent, _declaredExempt.keys.toSet());
      // ومُدخَلٌ تَعفَّنَ يَسقطُ كذلك: كلُّ مُستثنًى ما زال موضعَ جوالٍ فعلاً.
      for (final k in _declaredExempt.keys) {
        expect(sites.containsKey(k), isTrue,
            reason: 'استثناءٌ لملفٍّ لم يَعُدْ يَضَعُ رقماً: $k');
      }
    });

    test('(ج٣) كاتبُ التسجيلِ مُنادِيه واحدٌ وهو يُطبِّع', () {
      // سببُ استثناءِ `firebase_service` مشدودٌ لا مُدَّعى.
      final callers = sourcesIn('lib', atLeast: 120)
          .where((f) => !f.path.endsWith('firebase_service.dart'))
          .where((f) => f
              .readAsStringSync()
              .contains('signUpWithRealEmailAndPassword('))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toSet();
      expect(callers, {'lib/screens/signup_screen.dart'});
      final su = File('lib/screens/signup_screen.dart').readAsStringSync();
      expect(su, contains('saudiMobile(phone)'));
      expect(RegExp(r'phone:\s*normalizedPhone').hasMatch(su), isTrue,
          reason: 'التسجيلُ يُخزّنُ المُطبَّعَ لا النصَّ الخامّ');
    });

    test('(ج٦) عددُ الاستثناءِ **بالموضعِ** مشدودٌ — فثانٍ يُراجَع', () {
      // **اختبارُ قضمٍ أثبتَ أنّ استثناءً بالموضعِ يَأكلُ القاعدةَ**: توسيعُه
      // بموضعٍ واحدٍ يُخفي ارتداداً حقيقيّاً، و(ج٢) ملفّيٌّ فلا يَراه. فلا
      // حمايةَ إلّا أن يَبقى العددُ معلوماً — نمطُ «عددُ المُستثنياتِ مشدودٌ»
      // المسجَّلُ في حارسِ مساراتِ README.
      expect(_siteExempt.length, 1,
          reason: 'استثناءٌ ثانٍ بالموضعِ — يُراجَعُ بوعي، فهو يُعطّلُ (ج٥) '
              'عن ذلك الموضع');
    });

    test('(ج٥) كلُّ **موضعٍ** يُغذّيه القاعدةُ — لا «الملفُّ يُنادِيها»', () {
      // **ثقبٌ كشفَه اختبارُ قضمٍ**: أوّلُ صياغةٍ سألت «هل يُنادي الملفُّ
      // القاعدةَ؟»، فإعادةُ موضعٍ واحدٍ من سبعةٍ إلى `_phoneController.text`
      // الخامِّ مرَّت **خضراءَ** — الملفُّ ما زال يُنادِيها في الستّةِ
      // الباقية. وهو الدرسُ المسجَّلُ «كلُّ ملفٍّ يُنادي القاعدةَ ليس كلَّ
      // موضع». فالقيمةُ تُقتطَعُ من كلِّ موضعٍ ويُشترَطُ أن تَأتيَ منها.
      final bad = <String>[];
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final rel = f.path.replaceAll(r'\', '/');
        if (_declaredExempt.containsKey(rel)) continue;
        final code = stripComments(f.readAsStringSync());
        for (final m in _phoneSite.allMatches(code)) {
          final value = _resolve(code, _valueAfter(code, m.end));
          if (_rule.hasMatch(value)) continue;
          if (_siteExempt.contains('$rel|$value')) continue;
          bad.add('$rel: «$value»');
        }
      }
      expect(bad, isEmpty,
          reason: 'موضعُ جوالٍ لا تُغذّيه القاعدةُ — والملفُّ يُنادِيها في '
              'موضعٍ آخرَ فاكتفى الفحصُ الأعلى');
    });

    test('(ج٤) الكاشفُ يَعضُّ — مُجرَّبٌ على الأشكالِ التي تُعميه', () {
      // المصدرُ بعدَ الإصلاحِ نظيفٌ، فنجاحُ المقارنةِ وحدَها لا يُبرهِنُ أنّ
      // الكاشفَ يَرى موضعاً أصلاً.
      expect(_phoneSite.hasMatch("'client_phone': x,"), isTrue);
      expect(_phoneSite.hasMatch("'user_phone': x,"), isTrue);
      expect(_phoneSite.hasMatch("customerPhone: x,"), isTrue);
      expect(_phoneSite.hasMatch('"phone": x,'), isTrue);
      // ولا إيجابيّةً كاذبةً على قراءةٍ أو مقارنة:
      expect(_phoneSite.hasMatch("d['phone'] == null"), isFalse);
      expect(_phoneSite.hasMatch('final phone = d.phone;'), isFalse);
      // والقاعدةُ تُطابَقُ بحدِّ كلمةٍ لا بالاحتواء (فخُّ `packageFormErrorX`):
      expect(_rule.hasMatch('saudiMobileX(p)'), isFalse);
      expect(_rule.hasMatch('saudiMobile(p)'), isTrue);
    });
  });

  // ───────── (د) الخادمُ يُطبِّعُ قبلَ البادئة ─────────
  test('(د) `createTamaraCheckout` يُطبِّعُ **قبلَ** `+966`', () {
    final idx = File('functions/index.js').readAsStringSync();
    expect(idx, contains('require("./phone")'));
    final at = idx.indexOf('phoneLib.saudiE164(customerPhone)');
    expect(at, greaterThan(0), reason: 'التطبيعُ زالَ من مسارِ تمارا');
    final prefix = idx.indexOf(r'`+966${customerPhone}`');
    expect(prefix, greaterThan(at),
        reason: 'البادئةُ تَسبقُ التطبيعَ — فالتطبيعُ لا يَمنعُ شيئاً');
  });

  // ───────── (هـ) تعليمةٌ واحدةٌ في الأسطحِ الأربعة ─────────
  test('(هـ) الأسطحُ الأربعةُ تَطلبُ الصيغةَ نفسَها', () {
    // كانت ثلاثاً: تلميحُ التسجيلِ `5XXXXXXXX`، ورسالتُه «يبدأ بـ 05»،
    // وتلميحُ بطاقةِ الدفعِ «مثال: 0501234567» — وحوارُ «حسابي» بلا تلميحٍ.
    final su = File('lib/screens/signup_screen.dart').readAsStringSync();
    final pay = File('lib/screens/payment_summary_screen.dart')
        .readAsStringSync();
    final pro = File('lib/screens/profile_screen.dart').readAsStringSync();

    expect(su, contains('"0501234567"'),
        reason: 'تلميحُ حقلِ التسجيلِ لا يَطلبُ الصيغةَ القانونيّة');
    expect(stripComments(su), isNot(contains('5XXXXXXXX')),
        reason: 'التلميحُ القديمُ عادَ، فالشاشةُ تَطلبُ صيغتَين');
    expect(su, contains('يبدأ بـ 05'));
    expect(pay, contains('0501234567'));
    expect(pro, contains("hintText: '0501234567'"));
    // ومضادّةٌ: الشرحُ الذي يَقتبسُ الصيغةَ القديمةَ ما زال في الخامّ.
    expect(su, contains('5XXXXXXXX'),
        reason: 'زالَ شرحُ العطلِ، فالحجبُ في الفحصِ أعلاه بلا موضوع');
  });

  // ───────── (و) `normalizeDigits` مشترَكةٌ لا منسوخة ─────────
  test('(و) `normalizeDigits` تُستورَدُ ولا تُعرَّفُ ثانيةً في `lib/`', () {
    final pf = File('lib/utils/phone_format.dart').readAsStringSync();
    expect(pf, contains('show normalizeDigits'));
    final defs = sourcesIn('lib', atLeast: 120)
        .where((f) => RegExp(r'String normalizeDigits\(')
            .hasMatch(stripComments(f.readAsStringSync())))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toSet();
    expect(defs, {'lib/utils/catalog_number.dart'});
  });

  // ───────── (ز) شواهدُ التعليل ─────────
  group('(ز) شواهدُ التعليل — زوالُ أيٍّ منها يُراجِعُ القاعدةَ', () {
    test('(ز١) الخادمُ ما زال يُلحِقُ `+966` — وهو سببُ وجودِ القاعدة', () {
      final idx = File('functions/index.js').readAsStringSync();
      expect(idx, contains(r'`+966${customerPhone}`'));
    });

    test('(ز٢) `whatsappNumber` ما زالت متسامحةً — قارئةُ المستنداتِ القديمة',
        () {
      // المستنداتُ القائمةُ تَحملُ الصِيَغَ الخمسَ، وإصلاحُ الكاتبِ لا يُعيدُ
      // كتابتَها — فتضييقُ هذه القارئةِ يَقتلُ رابطَ واتساب لها.
      for (final row in _cases()) {
        final input = row[1] as String;
        if (row[2] == null) continue;
        expect(whatsappNumber(input), '966${(row[2] as String).substring(1)}',
            reason: 'صيغةٌ مقبولةٌ لا تُعالِجُها `whatsappNumber`: «$input»');
      }
    });

    test('(ز٣) مُنسِّقُ STC قائمٌ بذاتِه ولا يُعبَّأُ من `users.phone`', () {
      // المُطبِّعُ الرابعُ: **صحيحٌ** لأنّها تَكتبُ الرقمَ فيه من جديد، فلم
      // يُلمَس. ولو صارَ يُعبَّأُ من المخزَّنِ لَزِمَ إدخالُه في القاعدة.
      final stc = File('lib/screens/moyasar_stc_screen.dart').readAsStringSync();
      expect(stc, contains('_formatPhone'));
      expect(stc, isNot(contains('users')),
          reason: 'شاشةُ STC صارت تَقرأُ `users` — فيُراجَعُ استثناؤها');
    });

    test('(ز٤) مسارا تمارا مشروطانِ بمفتاحٍ افتراضُه `false` — حدُّ الكامن', () {
      for (final p in const [
        'lib/screens/payment_summary_screen.dart',
        'lib/screens/store_payment_screen.dart',
      ]) {
        final s = File(p).readAsStringSync();
        expect(RegExp(r"tamara_enabled'\]\s*as bool\?\s*\?\?\s*false")
                .hasMatch(s),
            isTrue,
            reason: 'افتراضُ `tamara_enabled` تغيّرَ في $p — فيُراجَعُ وصفُ '
                'الكامنِ في ترويسةِ `phone_format.dart`');
      }
    });
  });

  // ───────── (ح) الحوارُ لا يُغلَقُ على رقمٍ مرفوض ─────────
  test('(ح) حوارُ «حسابي» يَفحصُ **قبلَ** الإغلاقِ وقبلَ الكتابة', () {
    final pro = File('lib/screens/profile_screen.dart').readAsStringSync();
    final check = pro.indexOf('saudiMobile(phoneController.text) == null');
    expect(check, greaterThan(0), reason: 'فحصُ الصيغةِ زالَ من الحوار');
    final pop = pro.indexOf('Navigator.pop(ctx, true)');
    expect(pop, greaterThan(check),
        reason: 'الإغلاقُ يَسبقُ الفحصَ — فالفحصُ لا يَمنعُ شيئاً');
    final write = pro.indexOf("'phone': saudiMobile(phoneController.text)");
    expect(write, greaterThan(pop),
        reason: 'الكتابةُ تَسبقُ الإغلاقَ المشروط');
    // والخطأُ في الحقلِ لا في شريطٍ يُرسَمُ تحتَ الحوار.
    expect(pro, contains('errorText: phoneError'));
  });

  // ───────── (ط) شاشةُ الدفعِ تَفحصُ الصيغةَ في المسارَين ─────────
  test('(ط) الصيغةُ مفحوصةٌ في `_handlePayment` وفي بوّابةِ الدفعِ الأصليّ',
      () {
    // الأزرارُ الأصليّةُ تَتخطّى `_handlePayment` (تُنادي النجاحَ مباشرةً)،
    // فالفحصُ في موضعٍ واحدٍ يَترُكُ الآخرَ مفتوحاً.
    final pay = File('lib/screens/payment_summary_screen.dart')
        .readAsStringSync();
    expect(
        RegExp(r'saudiMobile\(_phoneController\.text\)\s*==\s*null')
            .allMatches(pay)
            .length,
        2,
        reason: 'فحصُ الصيغةِ في موضعٍ واحدٍ من اثنَين');
  });
}
