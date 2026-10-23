import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/zone_search.dart';

/// مناطقُ بشكلِ الإنتاج (٢٠٢٦-١٠-٢٤): «صبيا» مطفأة، و«الجوه» بإحداثيّاتٍ
/// مغلوطةٍ بعيدةٍ عن جازان، وأسماءٌ مكرّرة («المشاف» ثلاثاً).
List<Map<String, dynamic>> _zones() => [
      {
        'name': 'فيفا',
        'enabled': true,
        'centerLoc': const GeoPoint(17.2608, 43.1055)
      },
      {
        'name': 'الداير',
        'enabled': true,
        'centerLoc': const GeoPoint(17.332, 43.107)
      },
      {
        'name': 'صبيا',
        'enabled': false,
        'centerLoc': const GeoPoint(17.163, 42.646)
      },
      {
        'name': 'الجوه',
        'enabled': true,
        'centerLoc': const GeoPoint(21.918, 42.020)
      },
      {
        'name': 'الجوة',
        'enabled': true,
        'centerLoc': const GeoPoint(17.279, 43.137)
      },
      {
        'name': 'المشاف',
        'enabled': true,
        'centerLoc': const GeoPoint(17.223, 42.859)
      },
      {
        'name': 'المشاف',
        'enabled': true,
        'centerLoc': const GeoPoint(17.249, 42.884)
      },
      {
        'name': 'عثوان',
        'enabled': true,
        'centerLoc': const GeoPoint(17.331, 43.203)
      },
      {'name': 'بلا إحداثيات', 'enabled': true},
    ];

void main() {
  group('مطابقةُ أسماءِ مناطقِ الخدمة', () {
    test('«فيفاء» تَجدُ «فيفا» — ما كان يُعيدُ صفراً من محرّكِ البحث', () {
      final hits = matchZones(_zones(), 'فيفاء');
      expect(hits.map((h) => h.name), ['فيفا']);
    });

    test('الهمزةُ والتاءُ المربوطةُ و«ال» لا تُفرِّق', () {
      expect(matchZones(_zones(), 'داير').map((h) => h.name), ['الداير']);
      expect(normalizeArabicPlace('الجوة'), normalizeArabicPlace('الجوه'));
      expect(normalizeArabicPlace('فيفاء'), normalizeArabicPlace('فيفا'));
    });

    test('المنطقةُ المطفأةُ لا تَظهر — اختيارُها يُرفَضُ «خارج النطاق»', () {
      expect(matchZones(_zones(), 'صبيا'), isEmpty);
    });

    test('الاسمُ المكرّرُ يَظهرُ مرّةً واحدة', () {
      expect(matchZones(_zones(), 'المشاف').length, 1);
    });

    test('منطقةٌ بلا إحداثيّاتٍ لا تُعرَض (لا مكانَ نَنقلُ الخريطةَ إليه)', () {
      expect(matchZones(_zones(), 'إحداثيات'), isEmpty);
    });

    test('نصٌّ فارغٌ لا يُطابِقُ شيئاً', () {
      expect(matchZones(_zones(), '   '), isEmpty);
    });
  });

  group('مركزُ الخدمة', () {
    test('الوسيطُ لا يَجرُّه إدخالٌ مغلوط — يَبقى في جبالِ جازان', () {
      final c = serviceCenter(_zones())!;
      // كلُّ المناطقِ المفعّلةِ الصحيحةِ بين ١٧٫٢ و١٧٫٤ شمالاً؛ «الجوه» عند ٢١٫٩
      // كانت ستَجرُّ المتوسّطَ قرابةَ درجة.
      expect(c.lat, inInclusiveRange(17.2, 17.4));
      expect(c.lng, inInclusiveRange(42.8, 43.25));
    });

    test('المطفأةُ خارجَ الحساب، ولا مناطقَ ⇒ لا مركز', () {
      expect(
          serviceCenter([
            {
              'name': 'صبيا',
              'enabled': false,
              'centerLoc': const GeoPoint(17.1, 42.6)
            },
          ]),
          isNull);
      expect(serviceCenter(const []), isNull);
    });
  });

  group('التوصيل في شاشةِ الخريطة', () {
    final src =
        File('lib/screens/location_picker_screen.dart').readAsStringSync();

    test('نتائجُ المناطقِ تُعرَضُ قبلَ نتائجِ محرّكِ البحث', () {
      expect(src.contains('matchZones(_zones, query)'), isTrue);
      expect(src.contains('if (index < _zoneHits.length)'), isTrue);
    });

    test('فشلُ التحديدِ يَنقلُ الخريطةَ إلى مركزِ الخدمة', () {
      expect(src.contains('serviceCenter(_zones)'), isTrue);
      final failBranch = src.indexOf('_locateFailure = res.failure;');
      expect(src.indexOf('_centerOnServiceIfUnplaced();', failBranch),
          greaterThan(failBranch));
    });

    test('التحديدُ عند الفتحِ يَطلبُ الإذن (قرارُ المالك: تلقائيٌّ بلا زرّ)',
        () {
      expect(src.contains('_locateMe(userInitiated: true);\n    _loadZones();'),
          isTrue);
    });
  });
}
