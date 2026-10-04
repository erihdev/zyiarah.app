// حارس: **الإتاحةُ المجهولة ليست إتاحة.**
//
// حين يفشل `getHourlyAvailability` تُستبدَل شريطةُ التواريخ برسالةٍ حمراء
// («تعذّر تحميل المواعيد المتاحة») — وهذا صحيحٌ ومقصود: التعليقُ هناك يقول
// «لا نرسم تقويماً أخضر كاذباً. الأخضر وعدٌ بوجود سائق».
//
// لكنّ زرَّ «متابعة لملخص الحجز» لم يكن يعرف ذلك. والحقولُ تبقى عند العطل على
// افتراضاتها المتسامحة — `_maxOrdersPerDay = 10` و`_maxTeamsPerSlot = 5`
// وعدّاداتٌ فارغة — فتُرجع `_dateUnavailable` **false**: «اليومُ متاح». فالضغطُ
// كان يمضي إلى شاشةِ الدفع بـ`_selectedDate` الافتراضيّ، أي **تاريخٍ لم ترَه
// العميلةُ ولم تختره** لأنّ الشريطَ مستبدَل، لتُمنع هناك برسالةٍ ثانيةٍ
// مختلفة («تعذّر التحقق من توفّر الموعد»). شاشتان، رسالتان، ولا إعادةَ محاولة.
//
// الشاشتان الأخريان اللتان تحملان `_availabilityError` — باقاتُ الاشتراك
// وعاملاتُ المناسبات — محصّنتان بلا هذا الفحص: زرُّهما معطَّلٌ حتى تُختار كلُّ
// الزيارات من الشريط، والشريطُ مستبدَلٌ عند العطل. وهذه الشاشة وحدها لا تطلب
// اختياراً من الشريط (قرارُ المالك: لا وقتَ بدءٍ يختاره العميل).
//
// الحارسُ يثبّت الترتيب أيضاً: الفحصُ **قبل** `_firstFeasibleStart`، وإلّا
// سبقت رسالةُ «اكتملت مواعيد هذا اليوم» — دعوى امتلاءٍ لا نعرفها.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/screens/hourly_details_screen.dart').readAsStringSync();

  group('زرُّ المتابعة يعرف أنّ الإتاحة مجهولة', () {
    test('الفحصُ موجودٌ داخل _handleInitiateFlow', () {
      final i = src.indexOf('void _handleInitiateFlow()');
      expect(i, greaterThan(0));
      final body = src.substring(i, src.indexOf('  @override', i));
      expect(body.contains('if (_availabilityError) {'), isTrue,
          reason: 'المضيُّ بإتاحةٍ مجهولةٍ يأخذ العميلةَ إلى دفعِ تاريخٍ لم ترَه');
    });

    test('الفحصُ يسبق دعوى الامتلاء', () {
      final i = src.indexOf('void _handleInitiateFlow()');
      final body = src.substring(i, src.indexOf('  @override', i));
      final gate = body.indexOf('if (_availabilityError) {');
      final full = body.indexOf('final int? feasibleStart =');
      expect(gate, greaterThan(0));
      expect(full, greaterThan(0));
      expect(gate, lessThan(full),
          reason: '«اكتملت مواعيد هذا اليوم» دعوى امتلاءٍ لا نعرفها — '
              'يجب أن تسبقها رسالةُ «تعذّر التحميل»');
    });

    test('الرسالةُ هي رسالةُ الشريط نفسها، لا ثانيةً تناقضها', () {
      // الشريطُ فوق الزرِّ يقول «تعذّر تحميل المواعيد المتاحة» — وموضعان
      // يقولان شيئين مختلفين عن سببٍ واحدٍ هو عطلٌ بحدِّ ذاته.
      expect(src.contains('تعذّر تحميل المواعيد المتاحة'), isTrue);
      final n = 'تعذّر تحميل المواعيد المتاحة'
          .allMatches(src)
          .length;
      expect(n, greaterThanOrEqualTo(2),
          reason: 'الرسالةُ في الشريط وفي بوّابة الزرّ كلتيهما');
    });

    test('إعادةُ المحاولة متاحةٌ من الرسالة نفسها', () {
      final i = src.indexOf('if (_availabilityError) {');
      final body = src.substring(i, i + 900);
      expect(body.contains('SnackBarAction'), isTrue);
      expect(body.contains('onPressed: _loadAvailabilityFromServer'), isTrue,
          reason: 'رسالةُ عطلٍ بلا إعادةِ محاولةٍ تتركها عالقة');
    });

    test('الافتراضاتُ المتسامحة ما زالت كما هي (سببُ وجود البوّابة)', () {
      // لو شُدِّدت الافتراضاتُ يوماً (0 بدل 10/5) لصار العطلُ يقرأ «ممتلئ» —
      // عطلٌ آخرُ معاكس. البوّابةُ هي الحلُّ الصحيح في الحالتين، والفحصُ هنا
      // يوثّق أنّ المشكلةَ كانت تسامحَ الافتراض لا تشدّده.
      expect(src.contains('int _maxOrdersPerDay = 10;'), isTrue);
      expect(src.contains('int _maxTeamsPerSlot = 5;'), isTrue);
    });
  });

  group('الشاشتان الأخريان محصّنتان باختيار الزيارات', () {
    for (final f in const [
      'lib/screens/subscription_plans_screen.dart',
      'lib/screens/event_worker_packages_screen.dart',
    ]) {
      test('${f.split('/').last}: الزرُّ معطَّلٌ حتى تكتمل الزيارات', () {
        final s = File(f).readAsStringSync();
        expect(s.contains('_availabilityError'), isTrue,
            reason: 'لم تعد تعرف العطل — راجع البوّابة');
        // الشرطُ الذي يُبقي الزرَّ معطَّلاً: عددُ الزيارات المختارة = المطلوب.
        expect(s.contains('_scheduledVisits.length != visits'), isTrue,
            reason: 'سقط شرطُ اكتمالِ الزيارات — صارت الشاشةُ تمضي بإتاحةٍ '
                'مجهولةٍ كما كانت تمضي شاشةُ التنظيف المنزليّ');
      });
    }
  });
}
