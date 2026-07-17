// حارس: لا `Platform.` عارٍ من dart:io في شيفرة تعمل على الويب.
//
// ما رآه المالك: شاشة حمراء كاملة «Unsupported operation: Platform._operatingSystem»
// لحظة فتح ملخّص الدفع على كروم. `Platform.isIOS` من dart:io **يرمي على الويب** —
// فسؤالٌ بريء عن المنصّة يقتل الشاشة كلها. (لم يظهر من قبل لأن الدفع كان يُختبر على
// الجوال فقط — الويب أداة معاينة المالك.)
//
// القاعدة: كل قراءة لـ Platform.isX تمرّ بحارس kIsWeb أولاً — إمّا مباشرةً
// (`!kIsWeb && Platform.isIOS`) أو عبر علم محروس (`_isNativeIOS`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  test('كل Platform.isX في lib/ محروس بـ kIsWeb', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = _code(f.path);
      if (!code.contains('Platform.is') && !code.contains('Platform.operatingSystem')) {
        continue;
      }
      final rel = f.path.replaceAll(r'\', '/');
      for (final m in RegExp(r'Platform\.(is\w+|operatingSystem)').allMatches(code)) {
        // مقبول إن سبقه حارس `!kIsWeb &&` على نفس التعبير مباشرةً.
        final before = code.substring((m.start - 12).clamp(0, code.length), m.start);
        if (before.contains('kIsWeb &&')) continue;
        offenders.add('$rel ← ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty,
        reason: '\nPlatform من dart:io يرمي على الويب ويقتل الشاشة بشاشة حمراء.\n'
            'احرس كل قراءة بـ `!kIsWeb && Platform.isX`:\n'
            '  • ${offenders.join('\n  • ')}\n');
  });
}
