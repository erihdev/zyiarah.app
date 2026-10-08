// **الرقمُ المطبوعُ على العقدِ الموقَّعِ لم يَكن موجوداً في أيِّ قائمةٍ
// إداريّةٍ ولا قابلاً للعثورِ بأيِّ بحث.**
//
// خمسةُ أشكالٍ لرقمٍ واحد: الـPDF يَطبعُ الحقلَ المخزَّنَ `contractId`
// (`CTR-` + سبعةُ أرقام) وهو ما تَقرؤه العميلةُ وتَقولُه للدعم؛ وصفُّ
// القائمةِ عند الأدمنِ في التطبيقِ واللوحةِ كان `doc.id.substring(0, 8)`؛
// وصفُّ العميلةِ كان يَقطعُ المخزَّنَ إلى ثمانيةٍ (`CTR-1234` من أحدَ عشَر)؛
// واحتياطُ الـPDF الإداريِّ كان `'XXXX'`؛ وشاشةُ التوثيقِ تَعرضُ `CTR-XXXX`
// نائبةً قبلَ أن يُمنَحَ الرقمُ أصلاً.
//
// **والأثرُ الحيُّ في البحث**: تلميحُ الحقلِ في السطحَين يَقولُ «ابحث …
// أو **رقم العقد**»، ويُرشِّحُ معرّفَ المستندِ وحدَه — ولوحةُ الويبِ لم تَكن
// تَقرأُ الحقلَ المخزَّنَ إطلاقاً (ليس في `ContractRecord`). فعميلةٌ تَتّصلُ
// وتَقولُ الرقمَ المطبوعَ على عقدِها: لا يُطابِقُ شيئاً في أيِّ سطح.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/contract_ref.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// جدولُ الحالاتِ **واحدٌ بين اللغتَين**، ونسختُه المرجعيّةُ في
/// `admin_panel/src/utils/contractRef.test.ts` بين العلامتَين — والدارتُ هو
/// مَن يَقرأُ بقرارٍ مسجَّل: `node:fs` في ملفٍّ تحتَ `tsconfig.app.json` بلا
/// أنواعٍ فـ`npm run build` يَسقطُ بـTS2591 (مُتحقَّقٌ منه هنا لا مُفترَض)،
/// بينما `File()` في دارت تَقرأُ أيَّ مسار.
List<List<Object?>> _sharedCases() {
  final src =
      File('admin_panel/src/utils/contractRef.test.ts').readAsStringSync();
  final a = src.indexOf('CONTRACT_REF_CASES_START');
  final b = src.indexOf('CONTRACT_REF_CASES_END');
  expect(a, greaterThan(-1), reason: 'علامةُ الجدولِ زالت من ملفِّ الـTS');
  expect(b, greaterThan(a));
  final block = src.substring(a, b);
  // **من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس**: `indexOf('[')` يَلتقطُ
  // قوسَ تعليقِ النوعِ `[unknown, string, string][]` لا بدايةَ المصفوفة.
  final last = block.lastIndexOf(']');
  var depth = 0;
  var first = -1;
  for (var i = last; i >= 0; i--) {
    if (block[i] == ']') depth++;
    if (block[i] == '[') {
      depth--;
      if (depth == 0) {
        first = i;
        break;
      }
    }
  }
  expect(first, greaterThan(-1), reason: 'اقتطاعُ الجدولِ فشل');
  final json = block
      .substring(first, last + 1)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n')
      // فاصلةٌ متدلّيةٌ قبلَ الغلق — و`replaceAll` تَضعُ `$1` حرفيّاً فلا
      // تَفهمُ مجموعةَ التقاط، فخٌّ مسجَّلٌ في هذا المستودع.
      .replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m.group(1)!);
  return (jsonDecode(json) as List)
      .map((e) => (e as List).cast<Object?>())
      .toList();
}

void main() {
  final admin =
      File('lib/screens/admin/admin_contracts_screen.dart').readAsStringSync();
  final client =
      File('lib/screens/contracts_list_screen.dart').readAsStringSync();
  final signing =
      File('lib/screens/contract_signing_screen.dart').readAsStringSync();
  final panel = File('admin_panel/src/pages/Contracts.tsx').readAsStringSync();
  final rule = File('lib/utils/contract_ref.dart').readAsStringSync();

  test('(١) القاعدةُ سلوكاً — ثمانيةُ حالاتٍ، وقطعٌ لا يَرمي', () {
    final cases = _sharedCases();
    expect(cases.length, greaterThanOrEqualTo(8),
        reason: 'جدولُ الحالاتِ المشترَكُ انحلّ');
    for (final c in cases) {
      expect(contractRef(c[0], c[1] as String), c[2],
          reason: 'الحالة: ${c[0]} / ${c[1]}');
    }
    // و`substring(0, 8)` على معرّفٍ أقصرَ يَرمي — وهو ما كان مكشوفاً
    // في موضعَي الإدارة ومَحروساً في شاشةِ العميلةِ وحدَها.
    expect(() => contractRef(null, 'abc'), returnsNormally);
  });

  test('(٢) والمُطابَقةُ: الرقمُ المعروضُ أو المعرّفُ كاملاً', () {
    const stored = 'CTR-1234567';
    const id = 'aBcDeFgHiJkLmNoPqRsT';
    // الرقمُ المطبوعُ على العقد — وهو الحالةُ التي كان البحثُ يَعمى عنها.
    expect(contractRefMatches(stored, id, 'CTR-1234567'), isTrue);
    expect(contractRefMatches(stored, id, 'ctr-123'), isTrue);
    // والمعرّفُ كاملاً — فالروابطُ والسجلّاتُ القديمةُ تَحملُه.
    expect(contractRefMatches(stored, id, 'kLmNo'), isTrue);
    expect(contractRefMatches(stored, id, 'لا شيء'), isFalse);
    // وبحثٌ فارغٌ يُمرِّرُ الكلَّ (وإلّا فُرِّغت القائمةُ عند أوّلِ فتح).
    expect(contractRefMatches(stored, id, '   '), isTrue);
    // وبلا حقلٍ مخزَّنٍ يَبقى بادئةُ المعرّفِ مُطابَقةً.
    expect(contractRefMatches(null, id, 'abcdefgh'), isTrue);
  });

  test('(٣) وكلُّ **موضعِ** قراءةٍ للحقلِ يَمُرُّ بالقاعدة — لا كلُّ ملفّ', () {
    // **النطاقُ بالبيانِ لا بالنثر**: أوّلُ صياغةٍ أخذَت كلَّ ملفٍّ يَذكرُ
    // «رقم العقد» أو «المرجعي» في نصٍّ مرئيّ، فالتقطت خريطةَ **تسمياتِ**
    // سجلِّ التدقيقِ (`case 'contract_id': return "رقم العقد"` — ثابتٌ بلا
    // قيمة) و«الرقمَ المرجعيَّ» في حوارِ فشلِ الدفعِ، وهو مرجعُ **طلبٍ** لا
    // عقد. فالمِعيارُ قراءةُ الحقلِ نفسِه.
    //
    // **وبالموضعِ لا بالملفّ**: صياغةٌ ثانيةٌ طلبَت أن يَحويَ الملفُّ
    // `contractRef` في أيِّ مكان — فمَوضعٌ رابعٌ محلّيٌّ في ملفٍّ يُنادي
    // القاعدةَ في موضعٍ آخرَ كان يَمُرّ: «الحضورُ ليس القدرة». فالمشدودُ أن
    // يَكونَ **كلُّ** `['contractId']` وسيطاً أوّلَ للقاعدةِ، أو أحدَ
    // مفتاحَي إزالةِ التكرارِ المُعلَنَين (الفحصُ (٧) يَشدُّ شكلَهما).
    // **الإعفاءُ بالملفِّ والشكلِ معاً**: صياغةٌ ثالثةٌ أعفَت أيَّ موضعٍ
    // يَحويه الشكلُ أيّاً كان ملفُّه، فمرَّ شكلٌ رابعٌ محلّيٌّ في شاشةِ
    // الإدارةِ (`(data['contractId'] ?? doc.id).toString()`) — إعفاءٌ عامٌّ
    // بثوبِ إعفاءٍ مُعلَّل، أثبتَته قضمة.
    const dedupShapes = <String, String>{
      'contracts_list_screen.dart': "['contractId'] ?? doc.id",
      'client_dashboard.dart': "['contractId'] ?? d.id)",
    };
    var sites = 0;
    final offenders = <String>[];
    for (final f in sourcesIn('lib', atLeast: 150)) {
      if (f.path.endsWith('contract_ref.dart')) continue;
      final code = stripComments(f.readAsStringSync());
      for (final m in RegExp(r"\['contractId'\]").allMatches(code)) {
        sites++;
        final before = code.substring(0, m.start);
        final okCall = RegExp(r'contractRef(?:Matches)?\(\s*[\w.]*$')
            .hasMatch(before);
        final shape = dedupShapes[f.uri.pathSegments.last];
        final okDedup = shape != null &&
            code
                .substring(m.start,
                    (m.start + shape.length).clamp(0, code.length))
                .startsWith(shape);
        if (!okCall && !okDedup) {
          offenders.add('${f.uri.pathSegments.last}@${m.start}');
        }
      }
    }
    expect(sites, greaterThanOrEqualTo(5), reason: 'اشتقاقُ مَواضعِ الحقلِ انحلّ');
    expect(offenders, isEmpty,
        reason: 'موضعُ قراءةٍ للحقلِ لا يَمُرُّ بالقاعدة: $offenders');
    // وكلُّ إعفاءٍ مُعلَنٍ ما زال قائماً — فلا تَتعفّنُ القائمة.
    for (final e in dedupShapes.keys) {
      expect(
          sourcesIn('lib', atLeast: 150)
              .where((f) => f.uri.pathSegments.last == e)
              .length,
          1,
          reason: 'ملفُّ الإعفاءِ زال: $e');
    }
  });

  test('(٤) ولا شكلَ محلّيّاً باقياً: قطعٌ أعمى ولا نائبُ XXXX', () {
    for (final entry in {
      'admin': admin,
      'client': client,
      'panel': panel,
    }.entries) {
      final code = stripComments(entry.value);
      expect(code, isNot(contains("'XXXX'")),
          reason: '${entry.key}: عادَ نائبُ المرجع');
      expect(code, isNot(contains('substring(0, 8)')),
          reason: '${entry.key}: عادَ قطعٌ محلّيٌّ للمرجع');
      expect(code, isNot(contains('_shortRef')),
          reason: '${entry.key}: عادت نسخةٌ محلّيّةٌ من القاعدة');
    }
    expect(stripComments(panel), isNot(contains("split('-')[1]")),
        reason: 'اللوحة: عادَ شَقُّ المعرّفِ على الشرطة');
    // ومضادّةٌ: شرحُ القرارِ ما زال في الخامِّ حيث يَسكن — **ولكلِّ شكلٍ
    // محذوفٍ عبارتُه**: `contains('XXXX')` وحدَها كانت يُرضيها ذِكرُ
    // `CTR-XXXX` ولو زالَ شرحُ نائبِ الـPDF، وهي «موضعٌ آخرُ يُرضي الفحصَ»
    // واقعةً في حارسي أنا (أثبتَتها قضمة).
    expect(rule, contains("النصَّ الحرفيَّ `'XXXX'`"),
        reason: 'زالَ شرحُ نائبِ الـPDF الإداريّ');
    expect(rule, contains('`CTR-XXXX`'),
        reason: 'زالَ شرحُ نائبِ شاشةِ التوثيق');
    expect(rule, contains('`doc.id.substring(0, 8)`'),
        reason: 'زالَ شرحُ القطعِ المحلّيِّ في صفِّ الإدارة');
  });

  test('(٥) وشاشةُ التوثيقِ لا تَعرضُ رقماً قبلَ أن يُمنَح', () {
    final code = stripComments(signing);
    expect(code, isNot(contains('CTR-XXXX')),
        reason: 'عادَ رقمٌ مُلفَّقٌ على الشاشةِ التي تُوقَّعُ فيها');
    expect(code, contains('يُمنَح الرقم المرجعي عند التوثيق'));
    // وشاهدُ التعليل: المرجعُ **يُمنَحُ** هناك فعلاً ويُكتَبُ في الحقل.
    expect(code, contains("'CTR-"),
        reason: 'لم تَعُدْ شاشةُ التوثيقِ تَمنحُ المرجعَ — فالقاعدةُ تُراجَع');
    expect(code, contains("'contractId': contractId"),
        reason: 'المرجعُ لم يَعُدْ يُكتَبُ في الحقلِ الذي تَقرؤه القاعدة');
  });

  test('(٦) والبحثُ في السطحَين يَدَّعي «رقم العقد» ويُنفّذُه', () {
    // الدعوى هي ما جعلَ العطلَ عطلاً: لولا التلميحِ لكانَ نقصَ قدرةٍ لا
    // دعوى كاذبة. فهي مشدودةٌ — ولو زالَت يُراجَعُ التعليلُ لا يُسكَت.
    // **والدعوى تُقرَأُ حيث تُعرَض**: صياغةٌ أولى بحثَت عنها في الملفِّ
    // كلِّه — فتعليقي الذي يَقتبسُها يُرضيها، ومرَّت قضمةٌ أزالَتها من
    // التلميحِ نفسِه. فالمشدودُ نصُّ الحقلِ: `hintText:` و`placeholder=`.
    final adminHint =
        RegExp(r'hintText:\s*"([^"]*)"').allMatches(stripComments(admin));
    expect(adminHint.any((m) => m.group(1)!.contains('رقم العقد')), isTrue,
        reason: 'تلميحُ بحثِ التطبيقِ لم يَعُدْ يَدَّعي «رقم العقد»');
    final panelHint = RegExp(r'placeholder="([^"]*)"')
        .allMatches(stripComments(panel));
    expect(panelHint.any((m) => m.group(1)!.contains('رقم العقد')), isTrue,
        reason: 'تلميحُ بحثِ اللوحةِ لم يَعُدْ يَدَّعي «رقم العقد»');
    for (final entry in {'admin': admin, 'panel': panel}.entries) {
      expect(stripComments(entry.value), contains('contractRefMatches('),
          reason: '${entry.key}: البحثُ لا يَمُرُّ بالقاعدة');
    }
    // واللوحةُ تَقرأُ الحقلَ أصلاً — بلا ذلك تُقارِنُ `undefined` أبداً.
    expect(panel, contains('contractId?: string;'),
        reason: 'اللوحةُ لا تُحمّلُ الحقلَ، فالمُطابَقةُ عليه صمتٌ');
  });

  test('(٧) ومفاتيحُ إزالةِ التكرارِ تَبقى الهُويّةَ لا المرجعَ المقطوع', () {
    // `unique[data['contractId'] ?? doc.id]` مفتاحُ هُويّةٍ لا عرض: مرجعانِ
    // مقطوعانِ عند ثمانيةٍ قد يَتطابقانِ لمستندَين مختلفَين، فيَختفي عقدٌ
    // من قائمتِها أو من بطاقةِ «باقتي». فالمفتاحُ **لا يَمُرُّ بالقاعدة**
    // بقصدٍ لا سهواً — موضعانِ، وكلاهما مشدودٌ بشكلِه.
    expect(stripComments(client), contains("data['contractId'] ?? doc.id"),
        reason: 'مفتاحُ التكرارِ في «عقودي» تَغيّرَ — عقدٌ قد يَختفي');
    expect(
        stripComments(
            File('lib/screens/client_dashboard.dart').readAsStringSync()),
        contains("(m['contractId'] ?? d.id)"),
        reason: 'مفتاحُ التكرارِ في بطاقةِ «باقتي» تَغيّرَ');
  });
}
