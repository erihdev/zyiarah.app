import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/contract_visits.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **حارسُ رصيدِ زياراتِ العقد — الوسمُ يَتبعُ المصدر.**
///
/// ثلاثةُ أسطحٍ دارتيّةٍ تَعرضُ عددَ زياراتِ عقد، وواحدٌ منها كان يَقرأُ
/// الرصيدَ الحقيقيَّ: البطاقةُ في الرئيسيّةِ تَعرضُ «٣ / ١٢» من
/// `visits_remaining`، و«عقودي الإلكترونية» كانت تَقولُ «الزيارات
/// **المتبقية**: ١٢ زيارة» من `planVisits`، وورقةُ تفاصيلِ العقدِ عند
/// الأدمنِ «الزيارات **المتاحة**: ١٢ زيارة» كذلك.
///
/// والنطاقُ **مُشتَقٌّ** لا مكتوبٌ بيد: كلُّ ملفٍّ في `lib/` يَقرأُ أحدَ
/// الحقولِ الثلاثةِ يَجبُ أن يُناديَ القاعدةَ أو يَسكنَ قائمةَ إعفاءٍ
/// مُعلَّلةٍ، والمجموعتانِ تُقارَنانِ **كاملتَين** — فسطحٌ رابعٌ يُراجَعُ
/// بدلَ أن يُلفّقَ رقماً.
void main() {
  Map<String, dynamic> c({
    Object? remaining,
    Object? total,
    Object? plan,
  }) =>
      {
        if (remaining != null) 'visits_remaining': remaining,
        if (total != null) 'visits_total': total,
        if (plan != null) 'planVisits': plan,
      };

  group('(أ) القاعدةُ سلوكاً — ثلاثُ حالاتٍ نقيّة', () {
    test('رصيدٌ مكتوبٌ ⇒ «المتبقية» برقمِه لا بحجمِ الباقة', () {
      final v = contractVisitsView(c(remaining: 3, total: 12, plan: 12));
      expect(v.kind, ContractVisitsKind.remaining);
      expect(v.knowsBalance, isTrue);
      expect(v.count, 3);
      expect(v.total, 12);
      expect(v.label, 'الزيارات المتبقية');
      expect(v.text, '3 زيارة');
      expect(v.ratioText, '3 / 12');
      expect(v.progress, closeTo(0.25, 1e-9));
      expect(contractVisitsRemaining(c(remaining: 3, total: 12)), 3);
      expect(contractVisitsTotal(c(remaining: 3, total: 12)), 12);
    });

    test('صفرُ رصيدٍ معروفٌ لا مجهول', () {
      final v = contractVisitsView(c(remaining: 0, total: 8));
      expect(v.kind, ContractVisitsKind.remaining);
      expect(v.count, 0);
      expect(v.text, '0 زيارة');
      expect(v.progress, 0.0);
    });

    test('رصيدٌ غائبٌ وحجمٌ معروفٌ ⇒ «زيارات الباقة»، ولا شريط', () {
      final v = contractVisitsView(c(plan: 12));
      expect(v.kind, ContractVisitsKind.planOnly);
      expect(v.knowsBalance, isFalse);
      expect(v.count, 12);
      expect(v.label, 'زيارات الباقة');
      expect(v.ratioText, '12 زيارة',
          reason: 'شرطةُ النسبةِ تَدّعي رصيداً لم يُكتَبْ بعد');
      expect(v.progress, isNull);
    });

    test('لا رصيدَ ولا حجمَ ⇒ «—» بلا رقم', () {
      for (final d in [
        <String, dynamic>{},
        c(plan: 0),
        c(plan: -4),
        c(plan: 'كثير'),
        null,
      ]) {
        final v = contractVisitsView(d);
        expect(v.kind, ContractVisitsKind.unknown, reason: '$d');
        expect(v.count, isNull, reason: '$d');
        expect(v.text, '—', reason: '$d');
        expect(v.label, 'الزيارات', reason: '$d');
        expect(v.progress, isNull, reason: '$d');
      }
    });

    test('رصيدٌ يَتجاوزُ الحجمَ يُقَصُّ — لا «٦ / ٤»', () {
      final v = contractVisitsView(c(remaining: 6, total: 4));
      expect(v.count, 4);
      expect(v.ratioText, '4 / 4');
      expect(v.progress, 1.0);
    });

    test('رصيدٌ سالبٌ يُقرأُ صفراً', () {
      expect(contractVisitsRemaining(c(remaining: -2, total: 4)), 0);
      expect(contractVisitsView(c(remaining: -2, total: 4)).text, '0 زيارة');
    });

    test('نصٌّ رقميٌّ يُقرَأُ، وغيرُ الرقميِّ غيابٌ لا صفر', () {
      expect(contractVisitsRemaining(c(remaining: '3', total: '12')), 3);
      expect(contractVisitsTotal(c(total: '12')), 12);
      expect(contractVisitsRemaining(c(remaining: 'ثلاث', total: 12)), isNull);
      expect(contractVisitsView(c(remaining: 'ثلاث', total: 12)).kind,
          ContractVisitsKind.planOnly,
          reason: 'قيمةٌ تالفةٌ تُقرأُ غياباً فيُعرَضُ حجمُ الباقةِ بوسمِه');
    });

    test('`visits_total` يَغلِبُ `planVisits`، وغيابُه يَسقطُ إليه', () {
      expect(contractVisitsTotal(c(total: 8, plan: 12)), 8);
      expect(contractVisitsTotal(c(plan: 12)), 12);
    });
  });

  group('(ب) النطاقُ مُشتَقٌّ: كلُّ قارئٍ يُنادي القاعدةَ أو يُعلَّل', () {
    /// الملفّاتُ التي تَقرأُ أحدَ الحقولِ ولا تَعرضُ رصيداً — ولكلٍّ سببُه.
    /// (وملفُّ القاعدةِ نفسُه ليس فيها: هو **مُنادٍ** — يُنادي
    /// `contractVisitsTotal` داخلَ `contractVisitsRemaining`.)
    // **وزالَ `lib/models/user_model.dart` من القائمةِ (2026-10-08):** كان
    // يُحلّلُ `visits_remaining` على مستندِ **المستخدم** — مجموعَ عقودِه لا
    // عقداً بعينِه — وحُذفَ الحقلُ وجالبُه: صفرُ قارئٍ في أيِّ سطح، ومجموعٌ
    // بجوارِ ثلاثةٍ يَغلِبُ فيها آخرُ كاتب فـ«١٦ من ٨». وهذا الفحصُ هو ما
    // طلبَ حذفَ المُدخَلِ بنصِّه: «وإعفاءٌ لم يَعُدْ يَقرأُ يُحذَفُ من
    // القائمةِ فلا تَتعفّن».
    const Map<String, String> exempt = {
      'lib/screens/contract_signing_screen.dart':
          '`planVisits` حجمُ الباقةِ المُشتراةِ — يُكتَبُ على العقدِ ويُطبَعُ في نصِّ الاتفاقيّة',
      'lib/screens/checkout_screen.dart':
          '`planVisits` حِملٌ يُمرَّرُ إلى بيانات تمارا، لا عرضَ رصيد',
      'lib/screens/payment_summary_screen.dart':
          '`planVisits` حقلُ ودجةٍ يُمرَّرُ إلى إنشاءِ العقد',
      'lib/screens/subscription_plans_screen.dart':
          '`planVisits` معامَلٌ محلّيٌّ لسقفِ جدولةِ الزياراتِ قبلَ الشراء',
      'lib/screens/event_worker_packages_screen.dart':
          '`planVisits` معامَلٌ محلّيٌّ لسقفِ جدولةِ الزياراتِ قبلَ الشراء',
    };

    test('مجموعةُ القُرّاءِ غيرِ المُنادينَ = قائمةُ الإعفاءِ كاملةً', () {
      final readers = <String>{};
      final callers = <String>{};
      for (final f in sourcesIn('lib', atLeast: 120)) {
        final code = stripComments(f.readAsStringSync());
        final path = f.path;
        if (RegExp(r"visits_remaining|visits_total|planVisits").hasMatch(code)) {
          readers.add(path);
        }
        if (RegExp(r"\bcontractVisits(View|Remaining|Total)\s*\(")
            .hasMatch(code)) {
          callers.add(path);
        }
      }
      expect(readers.length, greaterThanOrEqualTo(8),
          reason: 'المسحُ انحلَّ — الحارسُ بلا موضوع');
      expect(callers.length, greaterThanOrEqualTo(3),
          reason: 'الأسطحُ الثلاثةُ تُنادي القاعدةَ');
      final silent = readers.difference(callers).toList()..sort();
      expect(silent, exempt.keys.toList()..sort(),
          reason: 'قارئٌ جديدٌ للحقولِ لا يُنادي القاعدةَ — يُراجَعُ بسببِه '
              'بدلَ أن يُلفّقَ رقماً، وإعفاءٌ لم يَعُدْ يَقرأُ يُحذَفُ من '
              'القائمةِ فلا تَتعفّن');
    });

    /// **والوسمُ والرقمُ كلاهما من القاعدة.** وسمٌ منها فوقَ رقمٍ يُقرَأُ
    /// خامّاً هو العطلُ بعينِه بثوبٍ أنظف، فالمشدودُ أنّ كلَّ سطحٍ يَأخذُ
    /// **الاثنَين**: `.label` ومعه `.text` أو `.ratioText`.
    test('الأسطحُ الثلاثةُ بأسمائها تَأخذُ الوسمَ والرقمَ من القاعدة', () {
      for (final p in const [
        'lib/screens/client_dashboard.dart',
        'lib/screens/contracts_list_screen.dart',
        'lib/screens/admin/admin_contracts_screen.dart',
      ]) {
        final code = stripComments(File(p).readAsStringSync());
        expect(RegExp(r"\bcontractVisits(View|Remaining)\s*\(").hasMatch(code),
            isTrue,
            reason: '$p لا يُنادي القاعدة');
        // `.text` وحدَه يُرضيه `someController.text` في الملفّ — «موضعٌ
        // آخرُ يُرضي الفحصَ». فالمُطابَقةُ على **مصدرِ** العضو: نداءُ
        // القاعدةِ مباشرةً، أو المتغيّرُ `visits` المُسنَدُ منها.
        final member = RegExp(
            r"(?:contractVisitsView\([^)]*\)|\bvisits)\.(label|text|ratioText)\b");
        final got = member.allMatches(code).map((m) => m.group(1)!).toSet();
        expect(got, contains('label'), reason: '$p وسمٌ مكتوبٌ بيد');
        expect(got.intersection({'text', 'ratioText'}), isNotEmpty,
            reason: '$p يَأخذُ الوسمَ من القاعدةِ والرقمَ من مكانٍ آخر');
      }
    });
  });

  group('(ج) لا نسخةَ من الوسمِ ولا قراءةَ رصيدٍ خارجَ القاعدة', () {
    const home = 'lib/utils/contract_visits.dart';

    test('وسمُ الرصيدِ يَسكنُ موضعاً واحداً في `lib/`', () {
      final offenders = <String>[];
      for (final f in sourcesIn('lib', atLeast: 120)) {
        if (f.path == home) continue;
        final code = stripComments(f.readAsStringSync());
        if (code.contains('الزيارات المتبقية') ||
            code.contains('الزيارات المتاحة') ||
            code.contains('زيارات الباقة')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'وسمُ الرصيدِ مكتوبٌ بيدٍ هناك — ونسختانِ تَنحرِفانِ عن '
              'المصدرِ الذي يُقرَأُ منه الرقم');
    });

    test('ولا سطحَ عرضٍ يَقرأُ `visits_remaining` مباشرةً', () {
      for (final p in const [
        'lib/screens/client_dashboard.dart',
        'lib/screens/contracts_list_screen.dart',
        'lib/screens/admin/admin_contracts_screen.dart',
      ]) {
        expect(stripComments(File(p).readAsStringSync()),
            isNot(contains('visits_remaining')),
            reason: '$p يَقرأُ الحقلَ خارجَ القاعدة — وهو كيف انحرفت '
                'الأسطحُ الثلاثةُ أصلاً');
      }
    });

    test('ومضادّةٌ: العبارتانِ القديمتانِ ما زالتا في الخامِّ (شرحُ العطل)',
        () {
      expect(File('lib/screens/contracts_list_screen.dart').readAsStringSync(),
          contains('الزيارات المتبقية'),
          reason: 'لو زالَ الشرحُ لَصارَ المُجرِّدُ بلا عمل، والفحصُ أعلاه '
              'يَمُرُّ لأنّه لا يَجدُ شيئاً');
      expect(
          File('lib/screens/admin/admin_contracts_screen.dart')
              .readAsStringSync(),
          contains('الزيارات المتاحة'));
    });
  });

  group('(د) شواهدُ التعليلِ الخادميّة', () {
    final idx = File('functions/index.js').readAsStringSync();
    final rewards = File('functions/rewards.js').readAsStringSync();

    test('التفعيلُ يَكتبُ العدّادَ والحجمَ على العقدِ نفسِه', () {
      expect(idx, contains('visits_remaining: pv'));
      expect(idx, contains('visits_total: pv'));
    });

    test('وتسويةُ الزيارةِ تُحرّكُ عدّادَ العقدِ لا عدّادَ المستخدمِ وحدَه',
        () {
      final i = rewards.indexOf('db.collection("contracts").doc(cId)');
      expect(i, greaterThan(0),
          reason: 'لو زالَ تحريكُ عدّادِ العقدِ لَصارَ `visits_remaining` '
              'عليه ساكناً — فيُراجَعُ التعليلُ لا يُسكَتُ الحارس');
      expect(rewards.substring(i, i + 160),
          contains('visits_remaining: FieldValue.increment(delta)'));
    });
  });

  group('(ه) شريطُ البطاقةِ مشروطٌ برصيدٍ معروف', () {
    final dash =
        stripComments(File('lib/screens/client_dashboard.dart').readAsStringSync());

    test('النسبةُ تُشتَقُّ من القاعدةِ لا تُحسَبُ محليّاً', () {
      expect(dash, contains('final double? progress = visits.progress;'));
      expect(dash, isNot(contains('(remaining / total)')),
          reason: 'حسابٌ محلّيٌّ يَعودُ ⇒ الأسطحُ تَنحرِفُ من جديد');
    });

    test('ولا شريطَ عند الجهل', () {
      final i = dash.indexOf('LinearProgressIndicator');
      expect(i, greaterThan(0));
      final before = dash.substring(0, i);
      expect(before.lastIndexOf('if (progress != null)'),
          greaterThan(before.lastIndexOf('SizedBox(height: 20)')),
          reason: 'شريطٌ ممتلئٌ فوقَ رصيدٍ مجهولٍ يَقولُ إنّ الباقةَ كاملةٌ '
              'ولم يَعُدَّها أحد');
    });
  });
}
