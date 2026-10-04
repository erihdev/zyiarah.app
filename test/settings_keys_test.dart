// حارس دائم: **كلُّ مفتاح في `SystemSettings` له قارئ.** لوحةُ الإعدادات تكتب
// `system_configs/main_settings`، ومفتاحٌ فيها لا يقرؤه أحد يعني أنّ الأدمن
// يضبطه ويرى «حُفظ بنجاح» ولا يتغيّر شيء — عطلٌ صامت لا يكشفه اختبارٌ ولا بناء.
//
// وقد تراكم هذا هنا على جولتين:
//   • الأولى: `vat_rate` و`min_wallet_balance` ومفاتيحُ الإشعارات الثلاثة —
//     الضريبة مثبّتة 15% في `functions/pricing.js`، فما كان للحقل أثر.
//   • 2026-10-04: `terms_url` — لا قارئَ له في التطبيق ولا الدوالّ ولا اللوحة،
//     ولا في `lib/` رابطُ شروطٍ مثبَّت كان يُفترض أن يقوده (شاشةُ الشروط تقرأ
//     `service_policies` بنداً بنداً)؛ و`commission_rate` — بلا حقلِ تحريرٍ
//     أصلاً، يُكتب ثابتاً بالقيمة 15 مع كلّ حفظ ولا يقرؤه أحد.
//
// الحارسُ عامّ: لا يُثبِّت أسماءً بعينها، بل يشترط لكلّ مفتاحٍ **قارئاً**. فمفتاحٌ
// جديدٌ بلا قارئ يسقط هنا بدل أن يصمت سنة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يُقنّع التعليقات مع حفظ الأطوال — التعليقُ أعلاه يذكر المفاتيح المحذوفة
/// بأسمائها، ومسحُ المصدر الخام يجعل الحارسَ يقرؤها «موجودة».
String _code(String path) {
  final s = File(path).readAsStringSync();
  final out = s.split('');
  var i = 0;
  while (i < s.length) {
    if (s[i] == '/' && i + 1 < s.length && (s[i + 1] == '/' || s[i + 1] == '*')) {
      final block = s[i + 1] == '*';
      var j = block ? s.indexOf('*/', i + 2) : s.indexOf('\n', i);
      j = j < 0 ? s.length : (block ? j + 2 : j);
      for (var k = i; k < j; k++) {
        out[k] = ' ';
      }
      i = j;
    } else {
      i++;
    }
  }
  return out.join();
}

List<File> _files(String dir, List<String> exts) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => exts.any((e) => f.path.endsWith(e)))
    .toList();

/// مفاتيح تخدم **اللوحةَ نفسها** لا التطبيق — مسموحةٌ صراحةً، واحدةً واحدة.
/// إضافةُ اسمٍ هنا قرارٌ متعمَّد، لا مهرب.
const Map<String, String> _panelOnly = {
  'support_url': 'زرُّ الدعم أعلى صفحة الإعدادات في اللوحة نفسها',
};

void main() {
  const String panel = 'admin_panel/src/pages/Settings.tsx';

  test('كلُّ مفتاح في SystemSettings له قارئ', () {
    final src = _code(panel);
    final i = src.indexOf('interface SystemSettings {');
    expect(i, greaterThan(-1), reason: 'اختفت SystemSettings — حدِّث الحارس');
    final block = src.substring(i, src.indexOf('}', i));
    final keys = RegExp(r'^\s*(\w+)\??\s*:', multiLine: true)
        .allMatches(block)
        .map((m) => m.group(1)!)
        .toSet();
    expect(keys, isNotEmpty, reason: 'لم تُقرأ أيّ مفاتيح — تغيّر الشكل');

    // المصادرُ التي يُعتدّ بقراءتها: التطبيق والدوالّ.
    final readers = <String>[
      ..._files('lib', ['.dart']).map((f) => _code(f.path)),
      _code('functions/index.js'),
    ];

    final orphans = <String>[];
    for (final k in keys) {
      if (_panelOnly.containsKey(k)) continue;
      final pat = RegExp(r'\b' + RegExp.escape(k) + r'\b');
      if (!readers.any(pat.hasMatch)) orphans.add(k);
    }

    expect(orphans, isEmpty,
        reason: '\n\nمفاتيحُ يحفظها الأدمن بلا أيّ أثر تشغيليّ — لا قارئَ لها\n'
            'في lib/ ولا في functions/index.js:\n  • ${orphans.join('\n  • ')}\n'
            'إمّا أن تُوصَل بقارئ، أو تُحذف، أو — إن كانت تخدم اللوحةَ نفسها —\n'
            'تُضاف إلى _panelOnly بسببٍ مكتوب.\n');
  });

  test('المسموحُ للّوحة وحدها مُستعمَلٌ فيها فعلاً', () {
    // قائمةٌ تُجيز ما لا يُستعمل تتعفّن — كما تعفّن شاهدُ COD في status_util.
    final src = _code(panel);
    for (final e in _panelOnly.entries) {
      final uses = RegExp(r'\b' + RegExp.escape(e.key) + r'\b')
          .allMatches(src)
          .length;
      expect(uses, greaterThan(2),
          reason: '${e.key} لم يعد مُستعمَلاً في اللوحة (${e.value}) — '
              'أزِله من _panelOnly ومن SystemSettings');
    }
  });

  test('الحقلان المحذوفان لا يعودان', () {
    final src = _code(panel);
    for (final k in ['terms_url', 'commission_rate']) {
      expect(src.contains(k), isFalse,
          reason: '$k عاد إلى اللوحة — لا قارئَ له، فعودتُه تعني حقلاً '
              'يحفظه الأدمن بلا أثر. إن صار له قارئ فاحذف هذا السطر.');
    }
  });
}
