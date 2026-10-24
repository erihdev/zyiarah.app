// موقعُ العميلةِ مرّةً للتطبيقِ كلِّه (قرار المالك 2026-10-24) —
// `lib/services/client_location.dart` و`lib/widgets/client_location_chip.dart`.
//
// كانت كلُّ شاشةِ خدمةٍ من السبع تُحدِّدُ الموقعَ بنفسِها وتَرسمُ سطرَها.
// الآن: الإذنُ مرّةً عند فتحِ التطبيق، والنقطةُ واسمُ المنطقةِ أعلى الرئيسيّة،
// والشاشاتُ تَقرأُ المحفوظ.
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/services/client_location.dart';
import 'package:zyiarah/services/zone_locator_service.dart';

const _fifa = {'name': 'فيفا'};
const _zones = [_fifa];
final _here = const GeoPoint(17.26, 43.10);

void main() {
  group('سلوكاً', () {
    test('الشاشاتُ تأخذُ المحفوظَ — لا GPS ثانٍ ولا نافذةُ إذنٍ ثانية', () async {
      final loc = ClientLocation.forTest();
      var calls = 0;
      final perms = <bool>[];
      loc.locator = (z, {bool requestPermission = true}) async {
        calls++;
        perms.add(requestPermission);
        return ZoneLocateResult.success(_here, _fifa);
      };
      await loc.ensure(_zones);
      final a = await loc.resolve(_zones);
      final b = await loc.resolve(_zones, requestPermission: true);
      expect(calls, 1, reason: 'كلُّ شاشةٍ تُعيدُ تحديدَ الموقع');
      expect(perms, [true], reason: 'الإذنُ يُطلَبُ عند الفتحِ وحدَه');
      expect(a.zoneName, 'فيفا');
      expect(b.zoneName, 'فيفا');
    });

    test('نداءانِ متزامنانِ يَنتظرانِ قراءةً واحدة', () async {
      final loc = ClientLocation.forTest();
      var calls = 0;
      final gate = Completer<ZoneLocateResult>();
      loc.locator = (z, {bool requestPermission = true}) {
        calls++;
        return gate.future;
      };
      final f1 = loc.ensure(_zones);
      final f2 = loc.resolve(_zones);
      expect(loc.isLocating, isTrue);
      gate.complete(ZoneLocateResult.success(_here, _fifa));
      await Future.wait([f1, f2]);
      expect(calls, 1);
      expect(loc.isLocating, isFalse);
    });

    test('فشلٌ محفوظٌ يُعادُ للشاشة، و«إعادة المحاولة» تَقرأُ من جديد', () async {
      final loc = ClientLocation.forTest();
      var calls = 0;
      loc.locator = (z, {bool requestPermission = true}) async {
        calls++;
        return calls == 1
            ? ZoneLocateResult.failed(LocateFailure.permissionDenied)
            : ZoneLocateResult.success(_here, _fifa);
      };
      await loc.ensure(_zones);
      expect((await loc.resolve(_zones)).failure, LocateFailure.permissionDenied);
      expect(calls, 1, reason: 'الشاشةُ تُعيدُ السؤالَ عن إذنٍ رُفض');
      final r = await loc.refresh(_zones, requestPermission: true, force: true);
      expect(r.isSuccess, isTrue);
      expect(calls, 2);
    });

    test('الخريطةُ تَغلبُ التحديثَ الصامت، والإعادةُ الصريحةُ تُلغيها', () async {
      final loc = ClientLocation.forTest();
      var calls = 0;
      const other = {'name': 'صبيا'};
      loc.locator = (z, {bool requestPermission = true}) async {
        calls++;
        return ZoneLocateResult.success(_here, other);
      };
      loc.setManual(_here, _fifa);
      expect(loc.isManual, isTrue);
      final silent = await loc.refresh(_zones);
      expect(silent.zoneName, 'فيفا', reason: 'التحديثُ الصامتُ كتبَ فوقَ اختيارِ الخريطة');
      expect(calls, 0);
      final forced = await loc.refresh(_zones, requestPermission: true, force: true);
      expect(forced.zoneName, 'صبيا');
      expect(loc.isManual, isFalse);
    });

    test('فشلٌ عابرٌ في التحديثِ الصامتِ لا يُطفئُ النقطةَ الخضراء', () async {
      final loc = ClientLocation.forTest();
      var calls = 0;
      loc.locator = (z, {bool requestPermission = true}) async {
        calls++;
        return calls == 1
            ? ZoneLocateResult.success(_here, _fifa)
            : ZoneLocateResult.failed(LocateFailure.timeout);
      };
      await loc.ensure(_zones);
      final r = await loc.refresh(_zones);
      expect(r.zoneName, 'فيفا', reason: 'مهلةُ GPS داخلَ مبنى محَت المنطقة');
      // والخروجُ الحقيقيُّ من النطاقِ يُكتَب.
      loc.locator = (z, {bool requestPermission = true}) async =>
          ZoneLocateResult.failed(LocateFailure.outOfServiceArea, location: _here);
      final out = await loc.refresh(_zones);
      expect(out.failure, LocateFailure.outOfServiceArea);
    });

    test('المستمعونَ يُبلَّغونَ عند كلِّ تغيُّر', () async {
      final loc = ClientLocation.forTest();
      loc.locator = (z, {bool requestPermission = true}) async =>
          ZoneLocateResult.success(_here, _fifa);
      var n = 0;
      loc.addListener(() => n++);
      await loc.ensure(_zones);
      expect(n, greaterThanOrEqualTo(2), reason: 'بدايةُ القراءةِ ونهايتُها');
      final before = n;
      loc.setManual(_here, _fifa);
      expect(n, before + 1);
    });
  });

  group('مصدراً', () {
    final screens = Directory('lib/screens')
        .listSync()
        .whereType<File>()
        .where((f) => f.readAsStringSync().contains('ZyiarahZoneLocationCard('))
        .toList();

    test('الشاشاتُ السبعُ تَقرأُ المصدرَ الواحدَ ولا تُحدِّدُ بنفسِها', () {
      expect(screens.length, greaterThanOrEqualTo(7),
          reason: 'الاشتقاقُ انهار — فالفحصُ أجوف');
      for (final f in screens) {
        final src = f.readAsStringSync();
        expect(src.contains('ZyiarahZoneLocator.locate('), isFalse,
            reason: '${f.path}: تُحدِّدُ الموقعَ بنفسِها');
        expect(src.contains('ClientLocation.instance.resolve('), isTrue,
            reason: '${f.path}: لا تَقرأُ المحفوظ');
        expect(src.contains('ClientLocation.instance.setManual('), isTrue,
            reason: '${f.path}: اختيارُ الخريطةِ لا يَصِلُ الرأس');
        expect(src.contains('retry: true'), isTrue,
            reason: '${f.path}: «إعادة المحاولة» تُعيدُ المحفوظَ الفاشل');
        expect(src.contains('تم تحديد موقعك تلقائياً'), isFalse,
            reason: '${f.path}: عادت رسالةُ التحديدِ داخلَ الشاشة');
      }
    });

    test('سطرُ الموقعِ لا يُرسَمُ إلّا حين لا موقعَ أصلاً', () {
      final card = File('lib/widgets/zone_location_card.dart').readAsStringSync();
      expect(
          card.contains(
              'if (isLocating || zoneName != null || failure == null) {\n      return const SizedBox.shrink();'),
          isTrue,
          reason: 'عاد «جارٍ تحديد موقعك…» أو «المنطقة: …» داخلَ الشاشة');
      expect(card.contains('failure == LocateFailure.outOfServiceArea'), isTrue,
          reason: 'خارجَ النطاقِ سطرانِ لشيءٍ واحد');
      expect(card.contains("'المنطقة: \$zoneName'"), isFalse);
    });

    test('الرئيسيّةُ تَحملُ النقطةَ واسمَ المنطقة، وهي وحدَها تَطلبُ الإذن', () {
      final dash = File('lib/screens/client_dashboard.dart').readAsStringSync();
      expect(dash.contains('ClientLocationChip()'), isTrue);
      final chip =
          File('lib/widgets/client_location_chip.dart').readAsStringSync();
      expect(chip.contains('_loc.ensure(_zones)'), isTrue,
          reason: 'لا طلبَ إذنٍ عند الفتح');
      expect(chip.contains('_loc.setManual(result, zone)'), isTrue,
          reason: 'التغييرُ من الرأسِ لا يَصِلُ الشاشات');
      expect(chip.contains('Color(0xFF059669)'), isTrue, reason: 'النقطةُ الخضراء');
    });
  });
}
