import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/banner_destination.dart';

import 'helpers/strip_comments.dart';

/// **بنرٌ يُضغَطُ فلا يَحدثُ شيء — والقاعدةُ مكتوبةٌ مرّتَين، والفالُّ وحدَه
/// افترق.**
///
/// مستندُ `promo_banners` يُرسَمُ في سطحَين: البنرُ الرئيسيُّ في
/// `client_dashboard` وقسمُ العروضِ في `offers_screen`. وقائمةُ الوجهاتِ
/// كانت متطابقةً في النسختَين، أمّا الفالُّ فلا: اللوحةُ تَقولُ «هذا الرابط
/// غير متاح حالياً»، وقسمُ العروضِ يُبقي `dest` على `null` فلا نقلَ ولا
/// كلمة. والحالةُ قابلةُ الوصولِ هي «رابط واتساب» بحقلِ رابطٍ فارغٍ —
/// والمُحرِّرُ كان يُسمّي الحقلَ «اختياري» ويَتحقّقُ من الصورةِ وحدَها.
void main() {
  final String dash =
      File('lib/screens/client_dashboard.dart').readAsStringSync();
  final String offers = File('lib/screens/offers_screen.dart').readAsStringSync();
  final String editor =
      File('lib/screens/admin/admin_banners_screen.dart').readAsStringSync();

  // ===== سلوكُ القاعدةِ (نقيّةٌ: بلا Firestore ولا ودجات) =====

  test('(أ) «صورة فقط» وغيابُ الحقلِ يُقرآنِ صمتاً لا «غير متاح»', () {
    expect(bannerTapOf({'routeType': 'none'}).kind, BannerTapKind.silent);
    expect(bannerTapOf({'routeType': ''}).kind, BannerTapKind.silent);
    expect(bannerTapOf({}).kind, BannerTapKind.silent);
    expect(bannerTapOf(null).kind, BannerTapKind.silent);
  });

  test('(ب) رابطٌ خارجيٌّ صالحٌ يُفتَح', () {
    final t = bannerTapOf({
      'routeType': 'whatsapp',
      'actionUrl': 'https://wa.me/966500000000',
    });
    expect(t.kind, BannerTapKind.externalUrl);
    expect(t.url, 'https://wa.me/966500000000');
  });

  test('(ج) **الحالةُ الحيّة**: «رابط واتساب» بلا رابطٍ ⇒ غير متاح لا صمت', () {
    expect(bannerTapOf({'routeType': 'whatsapp', 'actionUrl': ''}).kind,
        BannerTapKind.unavailable);
    expect(bannerTapOf({'routeType': 'whatsapp'}).kind,
        BannerTapKind.unavailable);
    expect(bannerTapOf({'routeType': 'whatsapp', 'actionUrl': '   '}).kind,
        BannerTapKind.unavailable);
  });

  test('(د) رابطٌ بلا مُخطَّطٍ غيرُ قابلٍ للفتح', () {
    expect(bannerExternalUrlIsUsable('wa.me/966500000000'), isFalse);
    expect(bannerExternalUrlIsUsable('https://wa.me/966500000000'), isTrue);
    expect(bannerExternalUrlIsUsable('whatsapp://send?phone=966500000000'),
        isTrue);
    expect(bannerExternalUrlIsUsable(''), isFalse);
    expect(bannerExternalUrlIsUsable(null), isFalse);
    expect(
        bannerTapOf({'routeType': 'whatsapp', 'actionUrl': 'wa.me/9665'}).kind,
        BannerTapKind.unavailable);
  });

  test('(هـ) كلُّ قيمةِ وجهةٍ مخزَّنةٍ تُحَلُّ إلى هدفِها', () {
    expect(kBannerServiceRoutes.length, greaterThanOrEqualTo(8));
    for (final e in kBannerServiceRoutes.entries) {
      final t = bannerTapOf({'routeType': e.key});
      expect(t.kind, BannerTapKind.service, reason: e.key);
      expect(t.service, e.value, reason: e.key);
    }
    // المرادفانِ القديمانِ لمستنداتِ الإنتاج.
    expect(kBannerServiceRoutes['/rug_cleaning'], BannerServiceTarget.sofaRug);
    expect(kBannerServiceRoutes['/ac'], BannerServiceTarget.acService);
  });

  test('(و) وجهةٌ لا نَعرفُها تُقالُ ولا تُبتلَع', () {
    expect(bannerTapOf({'routeType': '/car_interior'}).kind,
        BannerTapKind.unavailable);
    expect(bannerTapOf({'routeType': 'whatever'}).kind,
        BannerTapKind.unavailable);
  });

  // ===== حُرّاسُ المصدر: السطحانِ يُنادِيانِ القاعدةَ ولا نسخةَ إنلاين =====

  final Map<String, String> surfaces = {
    'client_dashboard': dash,
    'offers_screen': offers,
  };

  test('(ز) السطحانِ يُنادِيانِ `bannerTapOf` ولا يُعيدانِ تعدادَ `routeType`',
      () {
    expect(surfaces.length, 2);
    for (final e in surfaces.entries) {
      final String code = stripComments(e.value);
      expect(RegExp(r'\bbannerTapOf\s*\(').hasMatch(code), isTrue,
          reason: '${e.key}: لا يُنادي القاعدة');
      // **السطحُ لا يَقرأُ الحقلَين أصلاً.** فحصُ «لا يُطابِقُ «/store»»
      // كان إيجابيّةً كاذبةً: `/store` مسارُ تبويبٍ حقيقيٌّ في اللوحة
      // (`context.go('/store')`) لا مقارنةُ وجهةِ بنر. فالمشدودُ أن اسمَ
      // الحقلِ نفسِه زالَ من الشفرة — فلا تعدادَ ولا قراءةَ ثانية.
      expect(code.contains('routeType'), isFalse,
          reason: '${e.key}: ما زال يَقرأُ routeType بنفسِه');
      expect(code.contains('actionUrl'), isFalse,
          reason: '${e.key}: ما زال يَقرأُ actionUrl بنفسِه');
    }
  });

  test('(ح) السطحانِ يُغطّيانِ الأربعةَ، وفرعُ «غير متاح» يَقولُ النصَّ المشترك',
      () {
    for (final e in surfaces.entries) {
      final String code = stripComments(e.value);
      for (final k in BannerTapKind.values) {
        expect(code.contains('BannerTapKind.${k.name}'), isTrue,
            reason: '${e.key}: لا فرعَ لـ${k.name}');
      }
      expect(code.contains('kBannerUnavailableText'), isTrue,
          reason: '${e.key}: فرعُ «غير متاح» بلا نصٍّ — وهو ما افترقَ أصلاً');
    }
  });

  test('(ط) خريطةُ الهدفِ ← الشاشةِ متطابقةٌ في السطحَين وشاملةٌ', () {
    Map<String, String> screensIn(String src, String where) {
      final String code = stripComments(src);
      final int i = code.indexOf('Widget _bannerScreen(');
      expect(i, greaterThan(0), reason: '$where: لا مُبدِّلَ شاشات');
      // اقتطاعٌ بموازنةِ المعقوفةِ من `switch (target) {`
      final int b = code.indexOf('{', code.indexOf('switch (target)', i));
      int depth = 0;
      int j = b;
      while (j < code.length) {
        if (code[j] == '{') depth++;
        if (code[j] == '}') depth--;
        if (depth == 0) break;
        j++;
      }
      expect(j, lessThan(code.length), reason: '$where: اقتطاعٌ غيرُ مُوازَن');
      final String body = code.substring(b, j + 1);
      final Map<String, String> out = {};
      for (final m
          in RegExp(r'BannerServiceTarget\.(\w+)\s*=>\s*const\s+(\w+)')
              .allMatches(body)) {
        out[m.group(1)!] = m.group(2)!;
      }
      return out;
    }

    final a = screensIn(dash, 'client_dashboard');
    final b = screensIn(offers, 'offers_screen');
    expect(a.keys.toSet(), BannerServiceTarget.values.map((e) => e.name).toSet(),
        reason: 'client_dashboard: مُبدِّلٌ غيرُ شامل');
    expect(a, b, reason: 'السطحانِ يُوجِّهانِ الهدفَ نفسَه إلى شاشتَين');
  });

  test('(ي) السطحانِ يَفتحانِ الرابطَ بـexternalApplication وبلا بوّابةِ '
      'canLaunchUrl', () {
    for (final e in surfaces.entries) {
      final String code = stripComments(e.value);
      expect(code.contains('LaunchMode.externalApplication'), isTrue,
          reason: '${e.key}: بلا وضعٍ خارجيّ — يُفتَحُ واتساب في متصفّحٍ داخليّ');
      expect(code.contains('canLaunchUrl'), isFalse,
          reason: '${e.key}: بوّابةُ canLaunchUrl تُعيدُ false زائفاً على iOS');
    }
  });

  test('(ك) غيابُ LSApplicationQueriesSchemes — تعليلُ إسقاطِ canLaunchUrl', () {
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist.contains('LSApplicationQueriesSchemes'), isFalse,
        reason: 'ظهرَ المفتاحُ: يُراجَعُ قرارُ إسقاطِ canLaunchUrl لا يُسكَت');
  });

  // ===== المُحرِّر =====

  test('(ل) قائمةُ المُحرِّرِ مُشتَقّةٌ من الوجهاتِ المقروءةِ لا مكتوبةً بيد',
      () {
    final String code = stripComments(editor);
    expect(code.contains('kBannerTargetOptions'), isTrue);
    for (final route in kBannerServiceRoutes.keys) {
      expect(code.contains("'$route'"), isFalse,
          reason: 'المُحرِّرُ ما زال يَكتبُ «$route» بيدٍ فيُمكِنُه أن يَنحرِف');
    }
    // الخريطةُ تُغطّي كلَّ هدفٍ يَقرؤه البنر.
    expect(kBannerTargetOptions.keys.toSet(),
        BannerServiceTarget.values.toSet());
    for (final o in kBannerTargetOptions.values) {
      expect(kBannerServiceRoutes[o.route], isNotNull,
          reason: 'خيارٌ يَكتبُ «${o.route}» ولا يَقرؤه البنر');
      expect(o.label.trim(), isNotEmpty);
    }
  });

  test('(م) المُحرِّرُ يَرفُضُ وجهةً خارجيّةً بلا رابطٍ بنفسِ قاعدةِ القارئ',
      () {
    final String code = stripComments(editor);
    final int iGuard = code.indexOf('bannerExternalUrlIsUsable');
    expect(iGuard, greaterThan(0), reason: 'لا تحقّقَ من الرابطِ الخارجيّ');
    final int iWrite = code.indexOf("collection('promo_banners').add");
    expect(iWrite, greaterThan(0));
    expect(iGuard, lessThan(iWrite),
        reason: 'التحقّقُ بعدَ الكتابةِ لا يَمنعُ شيئاً');
    expect(code.contains('(اختياري)'), isFalse,
        reason: 'الحقلُ ما زال مُسمّىً «اختياري» فيَدعو إلى بنرٍ ميّت');
    // التسميةُ تَتبعُ الوجهةَ لا ثابتةً.
    expect(code.contains('selectedRoute == kBannerExternalRoute'), isTrue);
  });

  test('(ن) الشرحُ الذي يَقتبسُ الصيغةَ القديمةَ ما زال في النصِّ الخامّ', () {
    // «dest» وحدَها يُرضيها مسارُ الاستيرادِ `banner_destination.dart`،
    // فالمشدودُ هو الصيغةُ المُقتبَسةُ بعينِها.
    expect(dash.contains('الفالُّ'), isTrue,
        reason: 'زالَ الشرحُ الذي يَحكي افتراقَ الفالِّ');
    expect(offers.contains('`dest` على `null`'), isTrue,
        reason: 'زالَ الشرحُ الذي يَحكي `dest = null` الصامتة');
    expect(editor.contains('«اختياري»'), isTrue,
        reason: 'زالَ الشرحُ الذي يَحكي «(اختياري)»');
  });
}
