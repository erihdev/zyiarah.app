// ════════════════════════════════════════════════════════════════════════
// «المفتاحُ حاضرٌ والقدرةُ غائبة» — حقلٌ مصفوفيٌّ مثبَّتٌ فارغاً في حِملِ
// كتابة (2026-10-06)
//
// حقلُ المصفوفةِ **قائمةُ قرارات**، وتثبيتُه `[]` في حِملِ محرّرٍ يَعني
// «هذا المحرّرُ لا يَستطيعُ التعبيرَ عنه» — مع أنّ المفتاحَ مكتوبٌ فتَمرُّ
// مقارنةُ مجموعاتِ الحقولِ (الدواءُ المعتادُ لعائلةِ «حقلُ قرارٍ يَعرفُه
// مُحرِّرٌ واحد») **أخضرَ**. وهذا بعينُه ما حدثَ في `restricted_zones`:
// `Marketing.tsx` كان يَكتبُه `[]` ثابتاً فلا سبيلَ من اللوحةِ لحصرِ كوبونٍ
// بمنطقة، والخادمُ (`functions/coupons.js`) يُنفّذُ الحصرَ فعلاً.
//
// **والقاعدةُ كانت مُعلَنةً عامّةً ومُنفَّذةً على محرّرَين:** نصُّها في
// `coupon_contract_test` «لا مصفوفةً فارغةً حرفيّةً في حِملِ **أيِّ**
// محرّر»، وتنفيذُها كان على محرِّرَي الكوبوناتِ وحدَهما — «حارسٌ ضيّقٌ
// وقاعدةٌ عامّة» سابعَ مرّةٍ في هذا المستودع، وهذه المرّةَ في قاعدةٍ
// كتبتُها أنا. فالنطاقُ هنا **مُشتَقّ**: كلُّ منطقةِ وسائطَ لكلِّ نداءِ
// كتابةٍ في صفحاتِ اللوحةِ ومكوّناتِها، وكلُّ ملفٍّ دارتيٍّ تحتَ `lib/`.
//
// ومسحُ اليومِ أعطى **صفرَ عطل** (٣٩ منطقةَ كتابةٍ و١٥٩ ملفّاً) — فالقاعدةُ
// قائمةٌ في المستودعِ كلِّه، والمُضافُ هو القارئُ الذي يُبقيها كذلك.
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// يَحجبُ التعليقاتِ — ومنها `{/* … */}` في JSX، لأنّ حجبَ `//` وحدَه هو
/// ما جعلَ فحصاً آخرَ عقيماً هذه الليلةَ (تعليقٌ يَذكرُ ما يُفحَص).
String _mask(String src) {
  final masked = src.replaceAllMapped(
      RegExp(r'/\*[\s\S]*?\*/'), (m) => ' ' * m.group(0)!.length);
  return masked
      .split('\n')
      .map((l) {
        final t = l.trimLeft();
        return (t.startsWith('//') || t.startsWith('*')) ? ' ' * l.length : l;
      })
      .join('\n');
}

/// نداءاتُ الكتابةِ في Firestore من اللوحة.
const List<String> _writeCalls = <String>[
  'setDoc(',
  'addDoc(',
  'updateDoc(',
  'batch.set(',
  'batch.update(',
  'tx.update(',
  'tx.set(',
];

/// مناطقُ الوسائطِ **بموازنةِ الأقواس** — لا `indexOf(')')`، وهو الفخُّ
/// الذي أوقعَ حُرّاساً في هذا المستودعِ سبعَ مرّات.
List<({String call, int offset, String body})> _writeRegions(String src) {
  final out = <({String call, int offset, String body})>[];
  for (final w in _writeCalls) {
    var i = 0;
    while (true) {
      i = src.indexOf(w, i);
      if (i < 0) break;
      final open = i + w.length - 1;
      var depth = 0;
      for (var k = open; k < src.length && k < open + 4000; k++) {
        if (src[k] == '(') depth++;
        if (src[k] == ')') {
          depth--;
          if (depth == 0) {
            out.add((call: w, offset: i, body: src.substring(open, k + 1)));
            break;
          }
        }
      }
      i += w.length;
    }
  }
  return out;
}

int _lineOf(String src, int offset) =>
    src.substring(0, offset).split('\n').length;

void main() {
  group('لا حقلَ مصفوفيٍّ مثبَّتاً فارغاً في أيِّ حِملِ كتابة', () {
    final panelFiles = <String>[
      ...Directory('admin_panel/src/pages')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.tsx')),
      ...Directory('admin_panel/src/components')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.tsx')),
    ]..sort();

    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();

    test('(أ) المسحُ أصابَ شيئاً — فحارسٌ لا يَفحصُ أسوأُ من لا حارس', () {
      expect(panelFiles.length, greaterThanOrEqualTo(15),
          reason: 'صفحاتُ اللوحةِ لم تُقرَأ');
      expect(dartFiles.length, greaterThanOrEqualTo(120),
          reason: 'ملفّاتُ `lib/` لم تُقرَأ');
      var regions = 0;
      for (final f in panelFiles) {
        regions += _writeRegions(_mask(File(f).readAsStringSync())).length;
      }
      expect(regions, greaterThanOrEqualTo(30),
          reason: 'استخراجُ مناطقِ الكتابةِ انحلَّ إلى $regions — عقيم');
    });

    test('(ب) اللوحة: لا `key: []` داخلَ وسائطِ نداءِ كتابة', () {
      final hits = <String>[];
      for (final f in panelFiles) {
        final src = _mask(File(f).readAsStringSync());
        for (final r in _writeRegions(src)) {
          for (final m in RegExp(
                  '''(?:'|")?([A-Za-z_][A-Za-z0-9_]*)(?:'|")?\\s*:\\s*\\[\\s*\\]''')
              .allMatches(r.body)) {
            hits.add('$f:${_lineOf(src, r.offset)} ${r.call} '
                'key=${m.group(1)}');
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'حقلٌ مصفوفيٌّ مثبَّتٌ فارغاً — المفتاحُ حاضرٌ والقدرةُ '
              'غائبة:\n${hits.join('\n')}');
    });

    test('(ج) التطبيق: لا `\'key\': []` في أيِّ ملفٍّ تحتَ `lib/`', () {
      // في الدارتِ الحِملُ خريطةٌ بمفاتيحَ مُقتبَسة، وحالةُ الواجهةِ ليست
      // كذلك عادةً — فالمسحُ على الملفِّ كلِّه، وهو اليومَ نظيفٌ تماماً.
      final hits = <String>[];
      for (final f in dartFiles) {
        final src = _mask(File(f).readAsStringSync());
        for (final m
            in RegExp(r"'([a-zA-Z_][a-zA-Z0-9_]*)'\s*:\s*(?:<[^>]*>)?\[\s*\]")
                .allMatches(src)) {
          hits.add('$f:${_lineOf(src, m.start)} key=${m.group(1)}');
        }
      }
      expect(hits, isEmpty,
          reason: 'حقلٌ مصفوفيٌّ مثبَّتٌ فارغاً في التطبيق:\n'
              '${hits.join('\n')}');
    });

    test('(د) الاستخراجُ يَرى حِملاً حقيقيّاً — مُثبَتٌ على محرّرِ الكوبونات', () {
      // بلا هذا يُمكِنُ أن تَمرَّ (ب) لأنّ الاستخراجَ لا يَبلغُ أيَّ حِملٍ
      // أصلاً. المرجعُ هو الحِملُ الذي وُجدَ فيه العطلُ الأصليّ.
      final src = _mask(File('admin_panel/src/pages/Marketing.tsx')
          .readAsStringSync());
      final payloads = _writeRegions(src)
          .where((r) => r.body.contains('restricted_zones'))
          .toList();
      expect(payloads, isNotEmpty,
          reason: 'لم يَبلغِ الاستخراجُ حِملَ الكوبونِ — الفحصُ عقيم');
      expect(payloads.first.body.contains('newZones'), isTrue,
          reason: 'الحقلُ لم يَعُد يُكتَبُ من مُنتقي المناطق');
    });

    test('(هـ) المضادّة: قصّةُ القاعدةِ ما زالت مكتوبةً حيث وُجدت', () {
      // حجبُ التعليقاتِ هو ما يُجعلُ (ب) و(ج) ممكنَين، فيَلزمُ إثباتُ أنّ
      // الشرحَ باقٍ — وأنّ القارئَ يَجدُ الحادثةَ الأصليّةَ لا القاعدةَ
      // مُجرَّدةً. والشرحُ في حارسِ الكوبوناتِ لأنّ العطلَ وُجدَ هناك.
      final coupon = File('test/coupon_contract_test.dart').readAsStringSync();
      expect(coupon.contains('restricted_zones'), isTrue);
      expect(coupon.contains('editor_payload_capability_test'), isTrue,
          reason: 'لا إحالةَ من موضعِ العطلِ إلى الحارسِ العامّ');
    });
  });
}
