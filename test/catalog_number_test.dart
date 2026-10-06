import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/catalog_number.dart';

/// **باقةٌ تُحفَظُ بنجاحٍ ولا تُباع — `lib/utils/catalog_number.dart`.**
///
/// المحرِّرانِ الدارتيّانِ ولوحةُ الويبِ كانت تَكتبُ `?? 0.0` / `|| 0` على
/// `price`/`visits`/`hours`/`workers`، فقيمةٌ لا تَنحلُّ إلى رقمٍ تُخزَّنُ
/// صفراً مع «تمّ الحفظُ بنجاح». والفحصُ يَشدُّ القاعدةَ، ومرآتَها، ومُنادِيها
/// الثلاثةَ (مُشتَقّينَ لا مكتوبينَ بيد)، والشواهدَ الخادميّةَ والعميليّةَ
/// التي تُعلِّلُ كلَّ شرطٍ فيها.
String _code(String path) => File(path).readAsLinesSync().map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*'))
          ? ''
          : l;
    }).join('\n');

/// اقتطاعُ كتلةِ الحالاتِ المشترَكةِ من فحصِ الـTypeScript: من آخرِ `]` إلى
/// الوراءِ بموازنةِ الأقواس — `indexOf('[')` يَلتقطُ قوسَ **تعليقِ النوعِ**
/// `number | null][]` لا بدايةَ المصفوفة (فخٌّ مسجَّلٌ في `serviceMeta`).
List<List<Object?>> _sharedCases() {
  final src =
      File('admin_panel/src/utils/catalogNumber.test.ts').readAsStringSync();
  final a = src.indexOf('// ⟦CASES⟧');
  final b = src.indexOf('// ⟦/CASES⟧');
  if (a < 0 || b < 0 || b <= a) {
    throw StateError('علامتا كتلةِ الحالاتِ مفقودتانِ من فحصِ الـTS');
  }
  final block = src.substring(a, b);
  final end = block.lastIndexOf(']');
  if (end < 0) throw StateError('لا قوسَ إغلاقٍ في كتلةِ الحالات');
  var depth = 0;
  var start = -1;
  for (var i = end; i >= 0; i--) {
    final c = block[i];
    if (c == ']') depth++;
    if (c == '[') {
      depth--;
      if (depth == 0) {
        start = i;
        break;
      }
    }
  }
  if (start < 0) throw StateError('تعذّرَ موازنةُ أقواسِ كتلةِ الحالات');
  var json = block.substring(start, end + 1);
  // فاصلةٌ متدلّيةٌ قبل قوسِ الإغلاق، و`'` بدلَ `"`، و`1e16` مقبولٌ في JSON.
  json = json.replaceAll("'", '"');
  json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!);
  final decoded = jsonDecode(json) as List<dynamic>;
  return decoded.map((r) => (r as List<dynamic>).cast<Object?>()).toList();
}

/// جسمُ دالّةٍ بموازنةِ الأقواسِ من ترويسةٍ مُسمّاة — لا `indexOf('}')`، فذاك
/// يَقفُ عند أوّلِ قوسٍ مطابقٍ ولو كان داخلَ الترويسةِ نفسِها (فخُّ الحدِّ
/// المسجَّلُ في هذا المستودعِ خمسَ مرّات).
String _body(String path, String header) {
  final src = _code(path);
  final i = src.indexOf(header);
  if (i < 0) throw StateError('ترويسةٌ مفقودة: $header');
  var depth = 0;
  for (var j = i + header.length - 1; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(i, j + 1);
    }
  }
  throw StateError('تعذّرَ موازنةُ جسمِ: $header');
}

void main() {
  const rule = 'lib/utils/catalog_number.dart';
  const mirror = 'admin_panel/src/utils/catalogNumber.ts';
  const subsEditor = 'lib/screens/admin/admin_subscriptions_screen.dart';
  const eventEditor =
      'lib/screens/admin/admin_event_worker_packages_screen.dart';
  const panelEditor = 'admin_panel/src/pages/Contracts.tsx';

  group('قاعدةُ الحقلِ الرقميِّ في محرِّراتِ الباقات', () {
    test('(أ) الجدولُ المشترَكُ مع الـTypeScript — حالةً حالةً', () {
      final cases = _sharedCases();
      expect(cases.length, greaterThanOrEqualTo(15),
          reason: 'كتلةُ الحالاتِ انهارت — اقتطاعٌ فاشلٌ لا جدولٌ قصير');
      // **أصنافٌ لا عدد**: حدٌّ أدنى للطولِ يَكشفُ الانهيارَ ولا يَكشفُ
      // ضياعَ صنفٍ كامل — واختبارُ قضمٍ أثبتَ ذلك أخضرَ. فالمشدودُ هو تغطيةُ
      // الأصنافِ التي وُجد الجدولُ لها.
      final raws = cases.map((r) => r[0] as String).toList();
      bool anyWith(bool Function(int) p) => raws.any((s) => s.runes.any(p));
      expect(anyWith((c) => c >= 0x0660 && c <= 0x0669), isTrue,
          reason: 'لا حالةَ برقمٍ عربيٍّ-هنديٍّ — وهي الحالةُ الحيّةُ أصلاً');
      expect(anyWith((c) => c >= 0x06F0 && c <= 0x06F9), isTrue,
          reason: 'لا حالةَ برقمٍ فارسيّ');
      expect(anyWith((c) => c == 0x066B || c == 0x066C), isTrue,
          reason: 'لا حالةَ بفاصلةٍ أو فاصلِ آلافٍ عربيّ');
      expect(anyWith((c) => c == 0x200E || c == 0x200F || c == 0x061C), isTrue,
          reason: 'لا حالةَ بعلامةِ اتّجاهٍ غيرِ مرئيّة');
      for (final required in <String>['', '0', '-50', 'abc', '350 ر.س']) {
        expect(raws, contains(required),
            reason: 'صنفٌ ضائعٌ من الجدولِ: ${jsonEncode(required)}');
      }
      for (final row in cases) {
        final raw = row[0] as String;
        final expectedNum = row[1];
        final expectedInt = row[2];
        expect(positiveNum(raw), _eq(expectedNum),
            reason: 'positiveNum(${jsonEncode(raw)})');
        expect(positiveInt(raw), _eq(expectedInt),
            reason: 'positiveInt(${jsonEncode(raw)})');
      }
    });

    test('(ب) «N زيار» — نفسُ احتياطيِّ العميلِ والخادم', () {
      expect(visitsFromText('باقة 8 زيارات شهرياً'), 8);
      expect(visitsFromText('باقة ٨ زيارات شهرياً'), 8);
      expect(visitsFromText('4 زيارة'), 4);
      expect(visitsFromText('باقة ذهبية'), 0);
    });

    test('(ج) الحقلُ يَغلبُ النصَّ، والنصُّ احتياطٌ لا بديل', () {
      expect(resolvedVisits(visitsField: '6', text: 'باقة 8 زيارات'), 6);
      expect(resolvedVisits(visitsField: '', text: 'باقة 8 زيارات'), 8);
      expect(resolvedVisits(visitsField: '', text: 'باقة ذهبية'), 0);
      expect(resolvedVisits(visitsField: 'abc', text: 'باقة 8 زيارات'), 8);
    });

    test('(د) سعرٌ لا يَنحلُّ إلى رقمٍ يُرفَضُ ولا يُبتلَعُ صفراً', () {
      for (final bad in ['', '0', '-50', 'abc', '350 ر.س']) {
        expect(
            packageFormError(
                title: 'باقة',
                price: bad,
                visits: '4',
                hours: '4',
                text: 'باقة'),
            'السعر يجب أن يكون رقماً أكبر من صفر',
            reason: 'price=${jsonEncode(bad)}');
      }
      expect(
          packageFormError(
              title: 'باقة',
              price: '٣٥٠',
              visits: '٤',
              hours: '٤',
              text: 'باقة'),
          isNull,
          reason: 'الأرقامُ العربيّةُ تُقبَلُ لا تُرفَض');
    });

    test('(هـ) زياراتٌ بلا عددٍ تُرفَض، والنصُّ ما زال احتياطاً', () {
      expect(
          packageFormError(
              title: 'باقة ذهبية',
              price: '350',
              visits: '',
              hours: '4',
              text: 'باقة ذهبية مميزة'),
          'أدخِل عدد الزيارات — باقة بلا عدد زيارات لا يستطيع العميل شراءها');
      expect(
          packageFormError(
              title: 'باقة 8 زيارات',
              price: '350',
              visits: '',
              hours: '4',
              text: 'باقة 8 زيارات'),
          isNull);
      expect(
          packageFormError(
              title: 'باقة 8 زيارات',
              price: '350',
              visits: '0',
              hours: '4',
              text: 'باقة 8 زيارات'),
          'عدد الزيارات يجب أن يكون رقماً صحيحاً أكبر من صفر',
          reason: 'قيمةٌ مكتوبةٌ وغيرُ صالحةٍ لا تَسقطُ إلى النصّ');
    });

    test('(و) عاملاتُ المناسباتِ: يُفحَصُ متى مُرِّر وحدَه', () {
      expect(
          packageFormError(
              title: 'باقة',
              price: '350',
              visits: '4',
              hours: '4',
              workers: '0',
              text: 'باقة'),
          'عدد العاملات يجب أن يكون رقماً صحيحاً أكبر من صفر');
      expect(
          packageFormError(
              title: 'باقة',
              price: '350',
              visits: '4',
              hours: '4',
              text: 'باقة'),
          isNull,
          reason: 'باقاتُ الاشتراكِ لا تَحملُ الحقلَ فلا يُفحَص');
    });

    test('(ز) كلُّ كاتبٍ للمجموعتَين يُنادي القاعدةَ — نطاقٌ مُشتَقّ', () {
      final writers = <String>[];
      final roots = <String>['lib', 'admin_panel/src'];
      for (final root in roots) {
        for (final f in Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
                (f) => f.path.endsWith('.dart') || f.path.endsWith('.tsx'))) {
          if (f.path.contains('.test.')) continue;
          final src = _code(f.path);
          final namesCatalog = src.contains('subscription_packages') ||
              src.contains('event_worker_packages');
          if (!namesCatalog) continue;
          final writes = RegExp(
                  r"(addDoc|setDoc|updateDoc)\(|\.collection\('(subscription_packages|event_worker_packages)'\)\s*\.(add|doc)")
              .hasMatch(src);
          if (!writes) continue;
          // كتابةُ الحِملِ نفسِها: الحقولُ الأربعةُ معاً
          if (!(src.contains("'price'") || src.contains('price:'))) continue;
          if (!(src.contains("'visits'") || src.contains('visits:'))) continue;
          writers.add(f.path);
        }
      }
      expect(writers.toSet(), {subsEditor, eventEditor, panelEditor},
          reason: 'كاتبٌ رابعٌ للمجموعتَين: يُراجَعُ بدلَ أن يَبتلعَ صفراً');
      for (final w in writers) {
        // **شكلُ النداءِ لا حضورُ الاسم**: `contains('packageFormError')`
        // يُرضيه `packageFormErrorX` — اختبارُ قضمٍ أثبتَ ذلك أخضرَ.
        expect(RegExp(r'\bpackageFormError\s*\(').hasMatch(_code(w)), isTrue,
            reason: '$w لا يُنادي القاعدةَ');
      }
    });

    test('(ح) لا ابتلاعَ باقٍ في أيِّ كاتب — قدرةٌ لا اسم', () {
      for (final w in [subsEditor, eventEditor, panelEditor]) {
        final src = _code(w);
        for (final bad in <String>[
          'double.tryParse(priceCtrl',
          'int.tryParse(visitsCtrl',
          'int.tryParse(workersCtrl',
          'parseFloat(form.price)',
          'parseInt(form.visits)',
          'parseInt(form.workers)',
        ]) {
          expect(src.contains(bad), isFalse, reason: '$w ما زال يَبتلعُ: $bad');
        }
      }
    });

    test('(ط) المرآةُ تُصدِّرُ كلَّ ما يُصدِّرُه الأصل', () {
      final mirrorSrc = _code(mirror);
      for (final name in [
        'normalizeDigits',
        'positiveNum',
        'positiveInt',
        'visitsFromText',
        'resolvedVisits',
        'packageFormError',
      ]) {
        expect(_code(rule), contains(name), reason: 'الأصلُ فقدَ $name');
        expect(mirrorSrc, contains('export function $name'),
            reason: 'المرآةُ فقدَت $name');
      }
      // `positiveInt` مُشتَقّةٌ من `positiveNum` في الجهتَين — وإلّا انحرفت
      // على «3e2» و«4.0».
      expect(_code(rule), contains('final v = positiveNum(raw);'));
      expect(mirrorSrc, contains('const v = positiveNum(raw);'));
      // النطاقُ **جسمُ `positiveInt` وحدَه**: أوّلُ صياغةٍ مسحت الملفَّ كلَّه
      // فسقطت على `int.tryParse` **المشروعةِ** في `visitsFromText` — إبلاغٌ
      // خاطئٌ لا توثيقٌ (والتجريدُ يَحجبُ تعليقي الذي يُسمّيها).
      expect(_body(rule, 'int? positiveInt(String raw) {').contains('tryParse'),
          isFalse,
          reason: 'عودةُ `int.tryParse` إلى `positiveInt` تُعيدُ الانحرافَ '
              'عن الـTS على «3e2» و«4.0»');
      expect(File(rule).readAsStringSync(), contains('int.tryParse'),
          reason: 'الاسمُ ما زال في النصِّ الخامِّ (تعليلُ القرارِ ونداءٌ '
              'مشروعٌ في `visitsFromText`) — فتجريدٌ مُفرِطٌ لا يُجوِّفُ الفحصَ');
    });

    test('(ي) شواهدُ التعليلِ قائمةٌ: الخادمُ والعميلُ والقواعد', () {
      final idx = _code('functions/index.js');
      expect(idx, contains('if (!(base > 0) ||'),
          reason:
              'الخادمُ لم يَعُد يَرفُضُ سعرَ باقةٍ صفراً — يُراجَعُ التعليل');
      expect(idx, contains('if (pkgVisits <= 0) {'),
          reason: 'احتياطيُّ «N زيار» الخادميُّ زال — يُراجَعُ التعليل');
      expect(idx, contains('if (pkgVisits > 0 && Number(c.planVisits || 0)'),
          reason: 'فحصُ الزياراتِ الخادميُّ يُتخطّى عند الصفر — علّةُ كتابةِ '
              'المُستخرَجِ صريحاً');
      expect(idx, contains('Number(pkg.workers || 0) > 0 &&'),
          reason: 'فحصُ عددِ العاملاتِ يُتخطّى عند الصفر');
      final rules = _code('firestore.rules');
      expect(rules, contains("request.resource.data.get('planPrice', 0) > 0"));
      expect(rules, contains("request.resource.data.get('planVisits', 0) > 0"),
          reason: 'قاعدةُ إنشاءِ العقدِ هي ما يَرفُضُ باقةً صفريّةً عند '
              'العميلة — وهي علّةُ الرفضِ في المحرِّر');
      expect(_code('lib/screens/subscription_plans_screen.dart'),
          contains('visits <= 0 ||'),
          reason:
              'بوّابةُ زرِّ المتابعةِ عند العميلةِ زالت — يُراجَعُ التعليل');
    });

    test('(ك) حقولُ الرقمِ في المحرِّرِ الدارتيِّ ما زالت بلا مُنسِّقاتٍ', () {
      // التطبيعُ هو ما يُغني عن `inputFormatters` ويَقبلُ «٣٥٠» بدلَ رفضِها.
      // فلو أُضيفَ مُنسِّقٌ يَحصرُ الإدخالَ، فالقرارُ يُراجَعُ لا يُكرَّر.
      for (final f in [subsEditor, eventEditor]) {
        expect(_code(f).contains('inputFormatters'), isFalse,
            reason: '$f أُضيفَ له مُنسِّقُ إدخالٍ — يُراجَعُ التطبيعُ معه');
      }
    });
  });
}

Matcher _eq(Object? expected) {
  if (expected == null) return isNull;
  final n = expected as num;
  return closeTo(n.toDouble(), 1e-9);
}
