// كتالوجُ الخدماتِ: سطحٌ واحدٌ للبيانات، وسلوكُ الضغطةِ لكلِّ سطحٍ وحدَه.
//
// كان الكتالوجُ مكتوباً بيدٍ **مرّتَين** — شبكةُ لوحةِ العميلةِ وشاشةُ
// الاستكشافِ قبلَ الدخول — فافترقا:
//
//   • شاشةُ الزائرِ تَعرضُ **ستّاً** واللوحةُ **سبعاً**: «عاملات للمناسبات»
//     غائبةٌ كلّيّاً عن السطحِ الذي يَراه **مَن لم يُسجّلْ بعد** — أي الجمهورُ
//     الذي وُجدت الشاشةُ لأجلِه.
//   • وشارةُ سعرِ المكيفاتِ «حسب الطلب» — صياغةُ **طلبِ عرضِ السعرِ** الذي
//     أُزيلَ من الجذر، وتعليقُ اللوحةِ يَقولُه نصّاً. فزائرةٌ تَنتظرُ تسعيراً
//     يدويّاً والشاشةُ خلفَ الضغطةِ تُسعّرُ فوراً لكلِّ وحدة. ومعها الوصفُ
//     والأيقونة.
//   • و`numericPrice` **مُطالَبٌ بها في البطاقةِ ولا يَقرؤها جسمُها** —
//     سبعةُ مواضعَ تُمرّرُها، وأحدُها `50.0` والتعليقُ فوقَه يَقولُ إنّ
//     «من 50 ر.س» لم تَعُدْ تُطابقُ أيَّ سعرٍ خلفَ الضغطة: رقمٌ يَبيتُ في
//     حِملٍ لا قارئَ له.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/service_catalog.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

void main() {
  final dash = File('lib/screens/client_dashboard.dart').readAsStringSync();
  final guest =
      File('lib/screens/guest_explore_screen.dart').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('الكتالوجُ واحدٌ ومكتملٌ', () {
    test('(أ) مُعرّفٌ لكلِّ خدمةٍ وبطاقةٌ لكلِّ مُعرّف', () {
      expect(kServiceCatalog.length, ZyiarahService.values.length,
          reason: 'مُعرّفٌ بلا بطاقةٍ أو بطاقةٌ بلا مُعرّف');
      expect(kServiceCatalog.map((c) => c.id).toSet(),
          ZyiarahService.values.toSet());
      // «عاملات للمناسبات» هي ما غابَ عن شاشةِ الزائر — فحضورُها مشدودٌ بالاسم.
      expect(kServiceCatalog.map((c) => c.id),
          contains(ZyiarahService.eventWorkers));
    });

    test('(ب) لا بطاقةَ بنصٍّ فارغٍ ولا صورةٍ مفقودة', () {
      for (final c in kServiceCatalog) {
        expect(c.title.trim(), isNotEmpty, reason: '${c.id}: عنوانٌ فارغ');
        expect(c.subtitle.trim(), isNotEmpty, reason: '${c.id}: وصفٌ فارغ');
        expect(c.priceLabel.trim(), isNotEmpty, reason: '${c.id}: شارةٌ فارغة');
        expect(File(c.imagePath).existsSync(), isTrue,
            reason: '${c.id}: الصورةُ غيرُ موجودةٍ — ${c.imagePath}');
        // ووجودُها على القرصِ لا يَكفي: `pubspec.yaml` يُعدّدُ صورَ الخدماتِ
        // **واحدةً واحدةً** (لا `assets/images/` جملةً)، وصورةٌ غيرُ مُصرَّحٍ
        // بها تُرمى عند العرضِ فتُقرأُ البطاقةُ بأيقونةِ خطأ — بلا خطأِ بناء.
        expect(pubspec.contains(c.imagePath), isTrue,
            reason: '${c.id}: غيرُ مُصرَّحٍ بها في pubspec — ${c.imagePath}');
      }
    });

    test('(ج) صياغةُ طلبِ عرضِ السعرِ المهجورةُ لا تَعودُ للمكيفات', () {
      // القرارُ مسجَّلٌ في الشاشةِ نفسِها: «طلبٌ مباشرٌ مسعَّر، لا طلبُ عرضِ
      // سعر» — فشارةٌ تَقولُ «حسب الطلب» تُعِدُ بمسارٍ لا وجودَ له.
      final ac =
          kServiceCatalog.firstWhere((c) => c.id == ZyiarahService.acService);
      expect(ac.priceLabel.contains('حسب الطلب'), isFalse,
          reason: 'شارةُ المكيفاتِ عادت إلى صياغةِ عرضِ السعر');
      expect(ac.priceLabel, 'سعر لكل مكيف');
      // وشاهدُ التعليلِ: الشاشةُ ما زالت تُسعّرُ لكلِّ وحدةٍ من مستندِ المنطقة.
      final acScreen =
          File('lib/screens/ac_service_details_screen.dart').readAsStringSync();
      expect(acScreen.contains('acPriceField'), isTrue,
          reason:
              'لم تَعُدْ تُسعَّرُ لكلِّ وحدةٍ — فالشارةُ تُراجَعُ لا تُسكَت');
    });
  });

  group('السطحانِ يَقرآنِ الكتالوجَ ولا يُعيدانِ تعدادَه', () {
    test('(د) كلٌّ منهما يَبنيه من `kServiceCatalog`', () {
      for (final e in <String, String>{
        'client_dashboard': dash,
        'guest_explore_screen': guest,
      }.entries) {
        expect(RegExp(r'\bkServiceCatalog\b').hasMatch(stripComments(e.value)),
            isTrue,
            reason: '${e.key} لا يَقرأُ الكتالوج');
      }
    });

    test('(هـ) ولا نسخةَ مكتوبةً بيدٍ من الكتالوج', () {
      // الشكلُ القديمُ: قائمةُ `_ServiceItem` الخاصّةُ بشاشةِ الزائرِ وستُّ
      // بطاقاتٍ فيها، وسبعةُ نداءاتٍ تَحملُ نصوصَها حرفيّاً في اللوحة.
      expect(guest.contains('_ServiceItem'), isFalse,
          reason: 'قائمةُ شاشةِ الزائرِ الخاصّةُ عادت');
      for (final c in kServiceCatalog) {
        expect(stripComments(guest).contains("'${c.title}'"), isFalse,
            reason: 'عنوانٌ مكتوبٌ بيدٍ في شاشةِ الزائر: ${c.title}');
        expect(stripComments(guest).contains("'${c.priceLabel}'"), isFalse,
            reason: 'شارةُ سعرٍ مكتوبةٌ بيدٍ في شاشةِ الزائر: ${c.priceLabel}');
      }
      // وشاشةُ الزائرِ لا تُعدّدُ الوصفَ ولا الصورةَ كذلك.
      for (final c in kServiceCatalog) {
        expect(stripComments(guest).contains(c.imagePath), isFalse,
            reason: 'مسارُ صورةٍ مكتوبٌ بيدٍ في شاشةِ الزائر: ${c.imagePath}');
      }
    });

    test('(هـ٢) وكلُّ `serviceName` حرفيٍّ في السطحَين يُطابقُ عنوانَ الكتالوج',
        () {
      // مُبدِّلُ وجهةِ البانر في السطحَين يَبني الشاشتَين اللتَين تَأخذانِ
      // `serviceName` — وهما مشدودتانِ **متطابقتَين** في
      // `banner_destination_test (ط)` فلا تَنحرفانِ عن بعضِهما؛ وهذا يَشدُّ
      // ألّا تَنحرفا عن **الكتالوج**: بطاقةٌ تَقولُ «تنظيف منزلي» تَفتحُ
      // شاشةً عنوانُها غيرُه. (لم يُعَدْ بناءُ المُبدِّلَين: شفرةٌ سليمةٌ
      // يَحرُسُها فحصٌ قائمٌ، فلمسُها مخاطرةٌ بلا مقابل.)
      final titles = kServiceCatalog.map((c) => c.title).toSet();
      final offers = File('lib/screens/offers_screen.dart').readAsStringSync();
      var seen = 0;
      for (final e in <String, String>{
        'client_dashboard': dash,
        'offers_screen': offers,
      }.entries) {
        for (final m in RegExp(r'''serviceName:\s*["']([^"']+)["']''')
            .allMatches(stripComments(e.value))) {
          seen++;
          expect(titles, contains(m.group(1)),
              reason: '${e.key}: عنوانٌ لا يُطابقُ الكتالوج — ${m.group(1)}');
        }
      }
      expect(seen, greaterThanOrEqualTo(4),
          reason: 'الاستخراجُ انحلَّ — الفحصُ أعلاه عقيم');
    });

    test('(و) ولا `numericPrice` — حِملٌ لا قارئَ له', () {
      final all = sourcesIn('lib', atLeast: 100);
      // الحجبُ لازمٌ: وحدةُ الكتالوجِ تُسمّي المعاملَ في شرحِ إزالتِه،
      // فالفحصُ على الخامِّ يَسقطُ على توثيقِه — والمضادّةُ تَحتَه.
      final hits = all
          .where((f) =>
              stripComments(f.readAsStringSync()).contains('numericPrice'))
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(hits, isEmpty, reason: 'عادَ المعاملُ الميّت: $hits');
      expect(
          File('lib/utils/service_catalog.dart')
              .readAsStringSync()
              .contains('numericPrice'),
          isTrue,
          reason:
              'شرحُ إزالةِ المعاملِ زال — فلا يَعرفُ قارئٌ ما يَحرُسُه هذا');
      // و«من 50 ر.س» لم تَعُدْ تُطابقُ أيَّ سعرٍ خلفَ الضغطة.
      expect(RegExp(r'\b50\.0\b').hasMatch(stripComments(dash)), isFalse,
          reason: 'الرقمُ الثابتُ عادَ إلى بطاقاتِ اللوحة');
    });
  });

  group('سلوكُ الضغطةِ خاصٌّ بكلِّ سطحٍ ومُلزِم', () {
    test('(ز) وجهةُ اللوحةِ `switch` شامِلٌ بلا فرعٍ جامع', () {
      // الشمولُ هو ما يُسقِطُ الترجمةَ على خدمةٍ تُضافُ بلا وجهة — ففرعٌ
      // جامعٌ (`default` أو `_`) يُعيدُ العطلَ صامتاً.
      final code = stripComments(dash);
      final m = RegExp(r'Widget _screenFor\(ZyiarahServiceCard svc\)\s*=>\s*'
              r'switch \(svc\.id\)\s*\{')
          .firstMatch(code);
      final i = m?.start ?? -1;
      expect(i, greaterThan(0),
          reason: 'دالّةُ الوجهةِ غائبةٌ أو غيرُ تعبيريّة');
      var d = 0, end = -1;
      for (var k = code.indexOf('{', i); k < code.length; k++) {
        if (code[k] == '{') {
          d++;
        } else if (code[k] == '}') {
          d--;
          if (d == 0) {
            end = k;
            break;
          }
        }
      }
      expect(end, greaterThan(i));
      final body = code.substring(i, end);
      for (final v in ZyiarahService.values) {
        expect(body.contains('ZyiarahService.${v.name}'), isTrue,
            reason: 'لا فرعَ لـ${v.name} — والشمولُ هو الحارس');
      }
      expect(RegExp(r'^\s*(?:default|_)\s*=>', multiLine: true).hasMatch(body),
          isFalse,
          reason: 'فرعٌ جامعٌ يُبطِلُ الشمول');
    });

    test('(ح) وشاشةُ الزائرِ تَطلبُ الدخولَ لكلِّ بطاقة', () {
      // لا تَفتحُ شاشةَ خدمةٍ: الزائرُ بلا جلسةٍ فلا سعرَ ولا منطقةَ له.
      expect(stripComments(guest).contains('_showLoginPrompt'), isTrue);
      expect(RegExp(r'Navigator\.push').hasMatch(stripComments(guest)), isFalse,
          reason: 'شاشةُ الزائرِ تَفتحُ شاشةَ خدمةٍ بلا جلسة');
    });
  });
}
