// **`drivers/{id}.status` — حقلٌ كان يُكتَبُ بأربعةِ مواضعَ وثلاثِ مفرداتٍ
// ولا يَقرؤه شيءٌ في المستودعِ كلِّه.**
//
// ═══ ما كان ═══
//
// الكُتّابُ أربعةٌ، والمفرداتُ ثلاثٌ لحالةٍ واحدة:
//
//   * `order_service.updateOrderStatus` داخلَ معامَلةِ الانتقال —
//     `available` / `en_route` / `in_service`، مع كلِّ تغييرِ حالةٍ يَضغطُه
//     السائق.
//   * `driver_dashboard` عند الإقلاع — `idle`، مفردةٌ **رابعةٌ** لمعنى
//     `available` نفسِه.
//   * و`freeDriverOnOrderCancel` و`freeOldDriverOnReassign` خادميّاً —
//     `available`.
//
// والقُرّاءُ **صفر**. و`en_route`/`in_service`/`idle` لا ترِدُ في المستودعِ
// خارجَ مواضعِ كتابتِها إطلاقاً. والمِفتاحُ الوحيدُ الذي كان يُشبهُ قارئاً —
// `'status': driverData['status'] ?? 'offline'` في شاشةِ أداءِ الكوادر —
// مِفتاحُ خريطةٍ **لا يُعرَضُ ولا يُفرَزُ به ولا يُرشَّح**، وافتراضُه
// `offline` مفردةٌ **خامسةٌ لا يَكتبُها كاتب**: قارئٌ ظاهريٌّ يُوهِمُ أنّ
// للحقلِ معنًى متّفَقاً عليه.
//
// ═══ ولمَ الحذفُ هو الصوابُ لا التوصيل ═══
//
// الحالةُ الحيّةُ مَحمولةٌ ومقروءةٌ سلفاً بحقلَين: **`is_available`** —
// تَقرؤه شارةُ `Drivers.tsx` («متاح») وعدّادُ «السائقون المتاحون» —
// و**`current_order_id`** — يَقرؤه حارسُ المِلكيّةِ في معامَلةِ العميلِ وفي
// المُشغّلَين الخادميَّين. و`order_service` يَكتبُهما صحيحَين
// (`is_available: status == 'completed'`، و`current_order_id` يُصفَّرُ عند
// الإكمال) — **فلا عطلَ حيّاً**، و`status` تمثيلٌ ثالثٌ للحالةِ نفسِها
// بمفردةٍ مختلفة؛ فتوصيلُه إضافةُ قارئٍ لحقلٍ زائد.
//
// وخريطةُ الأسطول (`FleetVehicle.fromOrder`) تَقرأُ حالةَ **الطلبِ** لا
// السائق — مُتحقَّقٌ منه لا مُفترَض.
//
// والسابقةُ مسجَّلةٌ: `admin_panel/src/types/index.ts` حُذِفَ لهذا الشكلِ
// بعينِه (مفرداتٌ متّسقةٌ مع نفسِها وغيرُ مقروءة — وقد أعلنَ لهذا الحقلِ
// `'online' | 'offline' | 'busy' | 'suspended'`، تهجئةً **سادسةً**)،
// و`ZyiarahOrderProvider` حُذِفَ لمستمِعٍ قارئُه بلا قارئ.
//
// ═══ كامنٌ لا حيٌّ، ويُقالُ بحدِّه ═══
//
// الكلفةُ اليومَ كتابةُ حقلٍ زائدٍ مع كلِّ انتقالِ حالةٍ، داخلَ معامَلةٍ
// تَكتبُ أصلاً — لا تُذكَر. والمكسوبُ إزالةُ فخٍّ: مَن يَعرضُ الحقلَ أو
// يُرشِّحُ به غداً يَحصلُ على تعدادٍ غيرِ متّفقٍ عليه بين كاتبِيه.
//
// و`no_dead_code_test` **لا يَرى هذا**: يَفحصُ أعضاءَ دارتَ لا حقولَ
// Firestore — وهو ما جعلَ الحقلَ يَعيشُ بأربعةِ كُتّابٍ وصفرِ قُرّاء.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// المفرداتُ التي كانت تُكتَبُ قيمةً لـ`drivers/{id}.status`.
const _statusWords = ['en_route', 'in_service', 'idle'];

/// القيمةُ **مُقتبَسةً**: `in_service` عارياً يَقعُ داخلَ
/// `admin_services_screen.dart` في سطرِ استيراد، فالمسحُ العاري يُسقطُ
/// الفحصَ على شفرةٍ سليمة — وقد فعلَ في أوّلِ تشغيل.
RegExp _quoted(String w) => RegExp("['\"]$w['\"]");

/// جسمُ دالّةٍ **غيرِ** مُصدَّرةٍ في `index.js` — حتى الإعلانِ الذي يَليها.
String _fnBlock(String src, String name) {
  final i = src.indexOf('function $name');
  if (i < 0) throw StateError('«function $name» غيرُ موجود');
  var j = src.indexOf('\nasync function ', i + 10);
  final k = src.indexOf('\nfunction ', i + 10);
  if (j < 0 || (k >= 0 && k < j)) j = k;
  if (j < 0) j = src.length;
  final b = src.substring(i, j);
  if (b.length < 200) throw StateError('اقتطاعُ «$name» انحلّ');
  return b;
}

/// جسمُ دالّةٍ مُصدَّرةٍ في `index.js` — من إعلانِها إلى الإعلانِ الذي يَليه.
String _exportBlock(String src, String name) {
  final i = src.indexOf('exports.$name');
  if (i < 0) throw StateError('«exports.$name» غيرُ موجود');
  var j = src.indexOf('\nexports.', i + 10);
  if (j < 0) j = src.length;
  return src.substring(i, j);
}

void main() {
  final idx = File('functions/index.js').readAsStringSync();
  final panelDrivers =
      File('admin_panel/src/pages/Drivers.tsx').readAsStringSync();

  group('`drivers/{id}.status` حقلٌ محذوفٌ لا قارئَ له', () {
    test('(أ) لا كاتبَ له في أيِّ جهةٍ — والنطاقُ مُشتَقٌّ', () {
      // الكاشفُ: كتابةٌ على مستندِ سائقٍ تَحملُ مِفتاحَ `status`. والنطاقُ
      // `lib/` كلُّها + `functions/index.js` + صفحاتُ اللوحة.
      final offenders = <String>[];

      // ١) دارت: أيُّ حِملٍ يَذكرُ `'status'` في الملفِّ الذي يَلمسُ
      //    مجموعةَ `drivers` — ومعه الأعلامُ الحيّةُ كي لا يَلتبِسَ حِملُ
      //    الطلبِ بحِملِ السائق.
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final c = stripComments(f.readAsStringSync());
        if (!c.contains("collection('drivers')")) continue;
        // المفرداتُ التي كانت تُكتَب — **مُقتبَسةً** لا عارية: `in_service`
        // عارياً يُطابِقُ مسارَ استيرادِ `admin_services_screen.dart`، وقد
        // أسقطَ الفحصَ على شفرةٍ سليمةٍ في أوّلِ تشغيل.
        for (final w in _statusWords) {
          if (_quoted(w).hasMatch(c)) offenders.add('${f.path}: $w');
        }
        // وحِملُ السائقِ بعينِه: `driverUpdates` أو `ref.update({…})` بجوارِ
        // `is_available` — فـ`status` فيه هو الحقلُ المحذوف.
        for (final m
            in RegExp(r'\{[^{}]*is_available[^{}]*\}').allMatches(c)) {
          if (RegExp(r"'status'\s*:").hasMatch(m.group(0)!)) {
            offenders.add('${f.path}: حِملُ سائقٍ يَحملُ status');
          }
        }
      }

      // ٢) الخادم: حِملُ تحرير السائقِ في المُشغّلَين.
      for (final fn in ['freeDriverOnOrderCancel', 'freeOldDriverOnReassign']) {
        final b = stripComments(_exportBlock(idx, fn));
        for (final m
            in RegExp(r'\{[^{}]*is_available[^{}]*\}').allMatches(b)) {
          if (RegExp(r'\bstatus\s*:').hasMatch(m.group(0)!)) {
            offenders.add('index.js/$fn: حِملُ سائقٍ يَحملُ status');
          }
        }
      }

      // ٣) اللوحة: صفحةُ السائقينَ هي الكاتبُ الوحيدُ لمجموعةِ `drivers` فيها.
      for (final m in RegExp(r'\{[^{}]*is_available[^{}]*\}')
          .allMatches(stripComments(panelDrivers))) {
        if (RegExp(r'\bstatus\s*:').hasMatch(m.group(0)!)) {
          offenders.add('Drivers.tsx: حِملُ سائقٍ يَحملُ status');
        }
      }

      expect(offenders, isEmpty,
          reason: 'عادَ حقلٌ لا قارئَ له بمفرداتٍ غيرِ متّفَقٍ عليها: '
              '$offenders');
    });

    test('(ب) والكاشفُ يَعضُّ — يُجرَّبُ على شكلِ الكتابةِ بعينِه', () {
      // المصدرُ بعدَ الحذفِ نظيفٌ، فنجاحُ (أ) وحدَه لا يُبرهِنُ أنّ الكاشفَ
      // يَرى شيئاً. فيُجرَّبُ على الشكلَين اللذَين كانا في الشفرة.
      final payload = RegExp(r'\{[^{}]*is_available[^{}]*\}');
      const dartWas = "{if (ownsDriver) 'status': driverStatus, "
          "if (ownsDriver) 'is_available': status == 'completed'}";
      final mDart = payload.firstMatch(dartWas);
      expect(mDart, isNotNull, reason: 'الكاشفُ لا يَرى حِملَ دارت');
      expect(RegExp(r"'status'\s*:").hasMatch(mDart!.group(0)!), isTrue);

      const jsWas = '{ status: "available", current_order_id: null, '
          'is_available: true, }';
      final mJs = payload.firstMatch(jsWas);
      expect(mJs, isNotNull, reason: 'الكاشفُ لا يَرى حِملَ جافاسكربت');
      expect(RegExp(r'\bstatus\s*:').hasMatch(mJs!.group(0)!), isTrue);

      // ونفيُ إيجابيّةٍ كاذبة: حِملُ **طلبٍ** يَحملُ `status` ولا يَحملُ
      // `is_available`، فلا يُطابَقُ أصلاً.
      const orderPayload = "{'status': status, 'driver_id': driverId}";
      expect(payload.hasMatch(orderPayload), isFalse,
          reason: 'الكاشفُ يَلتقطُ حِملَ الطلبِ — إيجابيّةٌ كاذبة');

      // وأرضيّةُ قائمةِ المفردات: تفريغُها يُجوِّفُ (أ) و(ج) معاً بصمت.
      expect(_statusWords.length, 3,
          reason: 'قائمةُ المفرداتِ تغيّرت — يُراجَعُ النطاقُ لا يُفرَّغ');

      // والمفردةُ مُقتبَسةً: تُطابَقُ قيمةً، ولا تُطابَقُ داخلَ مسارِ استيراد.
      expect(_quoted('in_service').hasMatch("driverStatus = 'in_service';"),
          isTrue, reason: 'الكاشفُ لا يَرى القيمةَ المُقتبَسة');
      expect(
          _quoted('in_service')
              .hasMatch("import 'admin_services_screen.dart';"),
          isFalse,
          reason: 'الكاشفُ يَلتقطُ مسارَ استيراد — وهو ما أسقطَه أوّلَ مرّة');
    });

    test('(ج) والمفرداتُ الأربعُ زالت من المستودعِ كلِّه', () {
      // لا `en_route` ولا `in_service` ولا `idle` ولا `offline` كقيمةِ حالةِ
      // سائق. و`offline` ترِدُ مشروعةً في `user_facing_error` (انقطاعُ شبكةٍ)
      // فيُستثنى ملفُّها بسببِه، ومضادَّةٌ تُثبِتُ أنّ ورودَه هناك ما زال.
      final offenders = <String>[];
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final c = stripComments(f.readAsStringSync());
        for (final w in _statusWords) {
          if (_quoted(w).hasMatch(c)) offenders.add('${f.path}: $w');
        }
      }
      final srv = stripComments(idx);
      for (final w in _statusWords) {
        if (_quoted(w).hasMatch(srv)) offenders.add('index.js: $w');
      }
      expect(offenders, isEmpty, reason: 'مفردةٌ عادت: $offenders');

      final err =
          File('lib/utils/user_facing_error.dart').readAsStringSync();
      expect(err.contains("contains('offline')"), isTrue,
          reason: 'استثناءُ `offline` بلا موضوع — يُراجَعُ لا يُسكَت');

      // والقارئُ الميّتُ لا يَعود: `driverData['status']` كان المِفتاحَ
      // الوحيدَ الذي يُشبهُ قارئاً، وافتراضُه `offline` مفردةٌ لا يَكتبُها
      // كاتب. ومضادَّةٌ تُثبِتُ أنّ شرحَ إزالتِه ما زال في الخامّ، فلا
      // يُفرَّغُ الفحصُ من موضوعِه.
      final perf = File('lib/screens/admin/admin_staff_performance_screen.dart')
          .readAsStringSync();
      expect(stripComments(perf).contains("driverData['status']"), isFalse,
          reason: 'عادَ القارئُ الميّتُ — حقلٌ لا كاتبَ له بافتراضٍ لا أصلَ له');
      expect(perf.contains("driverData['status'] ?? 'offline'"), isTrue,
          reason: 'شرحُ الإزالةِ زال — المضادَّةُ بلا موضوع');
    });

    test('(د) شواهدُ التعليل: الحالةُ الحيّةُ ما زالت مَحمولةً ومقروءة', () {
      // زوالُ أيٍّ منها يُراجِعُ قرارَ الحذفِ لا يُسكِتُه.
      final os = stripComments(
          File('lib/services/order_service.dart').readAsStringSync());
      expect(os.contains("'is_available': status == 'completed'"), isTrue,
          reason: 'معامَلةُ العميلِ لم تَعُدْ تَكتبُ `is_available`');
      expect(os.contains("'current_order_id'"), isTrue,
          reason: 'معامَلةُ العميلِ لم تَعُدْ تَكتبُ `current_order_id`');
      expect(os.contains("['current_order_id']"), isTrue,
          reason: 'حارسُ المِلكيّةِ لم يَعُدْ يَقرأُ `current_order_id`');

      final srv = stripComments(idx);
      expect(
          RegExp(r'current_order_id !== event\.params\.orderId')
              .allMatches(srv)
              .length,
          greaterThanOrEqualTo(2),
          reason: 'حارسا المِلكيّةِ الخادميّانِ لم يَعُودا يَقرآنِ الحقل');

      // والمُسنِدُ لا يَلمسُ مستندَ السائقِ إطلاقاً — وهو ما يَجعلُ «لا
      // يُعدُّ مشغولاً بمهمّةٍ مجدولةٍ مستقبليّة» صحيحاً عن الحقلَين
      // الباقيَين، وهو مضمونُ الترويسةِ التي صُحِّحت في `order_service`.
      final asg = stripComments(_fnBlock(srv, '_assignDriverScheduled'));
      for (final f in ['is_available', 'current_order_id', 'driverRef']) {
        expect(asg.contains(f), isFalse,
            reason: 'المُسنِدُ صارَ يَلمسُ $f — يُراجَعُ مضمونُ الترويسة');
      }

      // بحدِّ كلمةٍ لا بالاحتواء: `is_availableZZ` **يَحوي** `is_available`،
      // فمرَّ اختبارُ قضمٍ أعادَ تسميةَ الحقلِ في اللوحةِ **أخضرَ** — فخُّ
      // `packageFormErrorX` بعينِه، واقعاً في حارسٍ كُتبَ لهذه الشريحة.
      final p = stripComments(panelDrivers);
      expect(RegExp(r'is_available(?![A-Za-z0-9_])').hasMatch(p), isTrue,
          reason: 'شارةُ اللوحةِ لم تَعُدْ تَقرأُ `is_available` — '
              'فالحالةُ الحيّةُ صارت بلا قارئ');
    });

    test('(هـ) وخريطةُ الأسطولِ تَقرأُ حالةَ **الطلبِ** لا السائق', () {
      // لو صارت تَقرأُ مستندَ السائقِ فالحذفُ يُراجَع.
      final fv = stripComments(
          File('lib/models/fleet_vehicle.dart').readAsStringSync());
      expect(fv.contains('fromOrder'), isTrue,
          reason: 'مُنشئُ الأسطولِ تغيّر');
      final screen = stripComments(
          File('lib/screens/admin/admin_fleet_map_screen.dart')
              .readAsStringSync());
      expect(screen.contains("collection('orders')"), isTrue,
          reason: 'خريطةُ الأسطولِ لم تَعُدْ تَقرأُ `orders`');
      expect(screen.contains("collection('drivers')"), isFalse,
          reason: 'خريطةُ الأسطولِ صارت تَقرأُ مستندَ السائق — '
              'يُراجَعُ قرارُ الحذف');
    });
  });
}
