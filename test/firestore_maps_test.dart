// حارس: خرائط Firestore المتداخلة تُطبَّع ولا تُكشَط بـ `as`.
//
// العطل الذي كشفه المالك: زرّ «تعديل المنطقة» لا يفتح — بلا رسالة. السبب:
//   data?['schedule'] as Map<String, dynamic>?
// الخرائط المتداخلة تصل بنوع Map<Object?, Object?> (القناة الأصلية على أندرويد،
// وبعض إصدارات الويب)، فالكشط الصلب يرمي TypeError **قبل** showDialog — زرٌّ ميت
// بصمت، وهو بالضبط صنف الفشل الذي تطارده هذه الجلسة كلها.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/firestore_maps.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  group('stringKeyedMap يطبّع بعمق', () {
    test('خريطة بمفاتيح Object تصير نصّية — بعمق كامل', () {
      final raw = <Object?, Object?>{
        'days': <Object?, Object?>{
          'sun': <Object?, Object?>{'open': 8, 'close': 14},
        },
        'dates': [
          <Object?, Object?>{'d': '2026-07-20'},
        ],
      };
      final m = stringKeyedMap(raw)!;
      expect(m, isA<Map<String, dynamic>>());
      expect(m['days'], isA<Map<String, dynamic>>());
      expect((m['days'] as Map)['sun'], isA<Map<String, dynamic>>());
      expect((m['dates'] as List).first, isA<Map<String, dynamic>>());
      expect(((m['days'] as Map)['sun'] as Map)['open'], 8);
    });

    test('غير الخرائط ⇒ null (حقل غائب أو تالف لا يُسقط الشاشة)', () {
      expect(stringKeyedMap(null), isNull);
      expect(stringKeyedMap('x'), isNull);
      expect(stringKeyedMap(3), isNull);
    });
  });

  test('المصدر: لا كشط `as Map<String, dynamic>` على حقول Firestore المتداخلة', () {
    // استثناء موثَّق: t['data'] في لوحة السائق خريطة دارت **محلية البناء**
    // ({'id': doc.id, 'data': doc.data()}) — قيمتها doc.data() العلوية وهي
    // Map<String, dynamic> أصلاً. ليست حقلاً متداخلاً من Firestore.
    const allowSafe = {
      "lib/screens/driver_dashboard.dart ← ['data']",
    };

    final offenders = <String>[];
    final pattern =
        RegExp("\\[['\"][A-Za-z_]+['\"]\\]\\s+as Map<String, dynamic>");
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = _stripComments(f.readAsStringSync());
      final rel = f.path.replaceAll(r'\', '/');
      for (final m in pattern.allMatches(code)) {
        final key = m.group(0)!.split(' as').first.trim();
        if (allowSafe.contains('$rel ← $key')) continue;
        final line = code.substring(0, m.start).split('\n').length;
        offenders.add('$rel:$line ← ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty,
        reason: '\nكشطٌ صلب على خريطة متداخلة من Firestore يرمي TypeError على '
            'أندرويد (وبعض إصدارات الويب) لحظة وجود الحقل — زرّ ميت بصمت.\n'
            'استعمل stringKeyedMap:\n  • ${offenders.join('\n  • ')}\n');
  });
}
