import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/order_lifecycle.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **«لا سائقَ لطلبٍ غيرِ مدفوع» كانت مُنفَّذةً في أربعةِ مساراتٍ خادميّةٍ
/// وغائبةً عن الخامسِ — وهو الوحيدُ الذي يَنقُرُه إنسان.**
///
/// المنفِّذونَ الأربعةُ: `onOrderWritten` لا يُسنِدُ إلّا على **انقلابِ**
/// `is_paid`؛ وكتلتا `sweepUnassignedPaidOrders` تتخطّيانِ `is_paid !== true`؛
/// و`capacity.countBookings` تتخطّاه فلا يَستهلكُ سعة؛
/// و`cancelStaleUnpaidOrders` تُلغيه بعد ثلاثين دقيقة. والمكشوفُ كان
/// `approveAndAssignOrder` — وله **سطحانِ** يَنقُرُهما الأدمنُ
/// (`admin_order_details_screen` و`admin_panel/src/pages/Orders.tsx`)، وكلاهما
/// يَفتحُ الإسنادَ لكلِّ `pending` بلا أيِّ نظرٍ إلى الدفع. شكلُ
/// `isAssignableDriver` بعينِه: مُنفَّذةٌ في اثنَين من أربعة، والمكشوفُ هو ما
/// يُنقَر.
///
/// وثلاثُ نتائجَ لإسنادِ غيرِ المدفوع، كلٌّ منها ضلعُها مشدودٌ أدناه:
///
///   * **(أ)** الإسنادُ يَكتبُ `scheduled`، ومكنسةُ الإلغاءِ تَستعلمُ
///     `status == "pending"` وحدَها — فالطلبُ **لا يُلغى أبداً**.
///   * **(ب)** `scheduled` داخلَ `CONFLICT_STATUSES` فيَشغلُ السائقَ، و
///     `countBookings` تتخطّى غيرَ المدفوعِ فلا يَستهلكُ سعةً — فتُعرَضُ
///     الساعةُ على عميلةٍ تَدفعُ ثمّ لا يُوجَدُ سائقٌ حرّ. وهي الحادثةُ
///     المسجَّلةُ بنصِّها: «يومٌ ظهرَ متاحاً، دُفِع، فلم يُوجَد سائقٌ مؤهَّل،
///     فعلِقَ الطلبُ حتى الاسترداد الآلي».
///   * **(ج)** شرطُ `remindClientsUpcomingAppointments` هو
///     `is_paid === true || driverAssigned` و`driverAssigned` يَكفيه
///     `scheduled` — فتَصِلُها «فريقنا في الطريق إليكِ» لخدمةٍ لم تُدفَع.
///
/// و`pending` بلا دفعٍ هي الحالةُ الطبيعيّةُ **قبلَ** الدفعِ لكلِّ طلبِ خدمة،
/// فالنافذةُ ثوانٍ في البطاقةِ وساعاتٌ في تمارا — ليست نظريّة.
void main() {
  final String idx = File('functions/index.js').readAsStringSync();
  final String cap = File('functions/capacity.js').readAsStringSync();
  // التجريدُ هنا **وقائيٌّ لا حامل**: قِيسَ باختبارِ قضمٍ يُجوِّفُه فلم يَسقطْ
  // شيءٌ اليوم — لا تعليقَ في `capacity.js` ولا في المُقتطَعاتِ أدناه يَذكرُ
  // صيغةً تُرضي فحصاً. ويَبقى بسببٍ مكتوبٍ لا بدعوى: «الحارسُ يَسقطُ على
  // توثيقِه» سُجِّلَ في هذا المستودعِ اثنتَي عشرةَ مرّةً، وترويسةُ
  // `capacity.js` تَشرحُ قرارَها بتسميةِ صِيَغٍ محظورة.
  final String capCode = stripComments(cap);
  final String slotsSrc = File('functions/slots.js').readAsStringSync();
  final String dartRule = File('lib/utils/order_lifecycle.dart').readAsStringSync();
  final String tsRule =
      File('admin_panel/src/utils/orderDispatch.ts').readAsStringSync();
  final String tsTest =
      File('admin_panel/src/utils/orderDispatch.test.ts').readAsStringSync();
  final String scr =
      File('lib/screens/admin/admin_order_details_screen.dart').readAsStringSync();
  final String panel =
      File('admin_panel/src/pages/Orders.tsx').readAsStringSync();

  /// جسمُ دالّةٍ مُصدَّرةٍ في `index.js` بموازنةِ الأقواس — لا شريحةَ عدِّ
  /// أحرفٍ ولا `indexOf` لأوّلِ مطابقة (فخُّ الحدِّ، وقد عضَّ هنا مراراً).
  String exportBody(String src, String name) {
    final int i = src.indexOf('exports.$name');
    expect(i, greaterThan(-1), reason: 'لم يُعثر على exports.$name');
    final int open = src.indexOf('{', src.indexOf('=>', i));
    expect(open, greaterThan(-1));
    int depth = 0;
    for (int k = open; k < src.length; k++) {
      if (src[k] == '{') depth++;
      if (src[k] == '}') {
        depth--;
        if (depth == 0) return src.substring(open, k + 1);
      }
    }
    fail('جسمٌ غيرُ متوازنٍ لـ$name');
  }

  group('بوّابةُ الدفعِ قبلَ إسنادِ سائق', () {
    test('(أ) القاعدةُ سلوكاً، وجدولُ الحالاتِ واحدٌ بين اللغتَين', () {
      final int b = tsTest.indexOf('// CASES_BEGIN');
      final int e = tsTest.indexOf('// CASES_END');
      expect(b, greaterThan(-1), reason: 'علامةُ بدايةِ الجدولِ زالت من فحصِ TS');
      expect(e, greaterThan(b), reason: 'علامةُ نهايةِ الجدولِ زالت من فحصِ TS');
      final String block = tsTest.substring(b, e);
      // الاقتطاعُ من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس: `indexOf('[')`
      // يَلتقطُ قوسَ تعليقِ النوعِ `[string, boolean][]` لا بدايةَ المصفوفة.
      final int close = block.lastIndexOf(']');
      expect(close, greaterThan(-1));
      int depth = 0;
      int openIdx = -1;
      for (int k = close; k >= 0; k--) {
        if (block[k] == ']') depth++;
        if (block[k] == '[') {
          depth--;
          if (depth == 0) {
            openIdx = k;
            break;
          }
        }
      }
      expect(openIdx, greaterThan(-1), reason: 'جدولٌ غيرُ متوازن');
      String json = block.substring(openIdx, close + 1);
      json = json.replaceAll("'", '"');
      json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m[1]!);
      final List<dynamic> cases = jsonDecode(json) as List<dynamic>;
      expect(cases.length, greaterThanOrEqualTo(7),
          reason: 'جدولُ الحالاتِ انهارَ — الفحصُ يَصيرُ أخضرَ أجوف');

      Object? valueFor(String tag) {
        switch (tag) {
          case 'true':
            return true;
          case 'false':
            return false;
          case 'absent':
            return (<String, Object?>{})['is_paid'];
          case 'null':
            return null;
          case 'string-true':
            return 'true';
          case 'zero':
            return 0;
          case 'one':
            return 1;
        }
        fail('صنفٌ لا يَعرفُه الدارت: $tag — الجدولُ افترقَ');
      }

      // أصنافٌ مُسمّاةٌ لا حدٌّ عدديٌّ وحدَه: فقدُ صنفٍ لا يُكشَفُ بالطول.
      final Set<String> tags =
          cases.map((c) => (c as List<dynamic>)[0] as String).toSet();
      for (final must in const [
        'true',
        'false',
        'absent',
        'null',
        'string-true',
      ]) {
        expect(tags, contains(must), reason: 'صنفٌ لازمٌ سقطَ من الجدول: $must');
      }

      for (final c in cases) {
        final List<dynamic> row = c as List<dynamic>;
        final String tag = row[0] as String;
        final bool allowed = row[1] as bool;
        expect(orderPaidForDispatch(valueFor(tag)), allowed,
            reason: 'الحالةُ «$tag» تَختلفُ عن جدولِ الـTS');
      }
    });

    test('(ب) ونصُّ الرفضِ واحدٌ في الثلاثةِ حرفاً بحرف', () {
      expect(dartRule.contains("'$kUnpaidDispatchRefusal'"), isTrue,
          reason: 'الثابتُ الدارتيُّ لا يَحملُ النصَّ المُعلَن');
      expect(tsRule.contains("'$kUnpaidDispatchRefusal'"), isTrue,
          reason: 'نصُّ مرآةِ اللوحةِ افترقَ عن الدارت');
      expect(idx.contains('"$kUnpaidDispatchRefusal"'), isTrue,
          reason: 'نصُّ الخادمِ افترقَ عن الدارت');
    });

    test('(ج) والخادمُ يَرفضُ في موضعَين: قبلَ المعاملةِ وذرّياً داخلَها', () {
      final String body = stripComments(exportBody(idx, 'approveAndAssignOrder'));
      final int n =
          RegExp(r'is_paid\s*!==\s*true').allMatches(body).length;
      expect(n, 2,
          reason: 'الرفضُ يَجبُ أن يَكونَ مرّتَين — قبلَ المعاملةِ '
              'وبقراءةٍ طازجةٍ داخلَها (استردادٌ أثناءَ العمليّة)؛ وُجد $n');
      expect(
          RegExp(r'UNPAID_DISPATCH_REFUSAL').allMatches(body).length, 2,
          reason: 'الموضعانِ يَستعملانِ الثابتَ لا نصّاً مكتوباً بيد');
      // المضادَّةُ: الصيغةُ ما زالت في الخامِّ (الحارسُ يَقرأُ المُجرَّد).
      expect(idx.contains('is_paid !== true'), isTrue);
    });

    test('(د) والفحصُ الذرّيُّ يَسبقُ أيَّ كتابةٍ في المعاملة', () {
      final String body = exportBody(idx, 'approveAndAssignOrder');
      final int tx = body.indexOf('runTransaction');
      expect(tx, greaterThan(-1));
      final String txPart = body.substring(tx);
      final int check = txPart.indexOf('fd.is_paid !== true');
      final int write = txPart.indexOf('tx.update(orderRef');
      expect(check, greaterThan(-1),
          reason: 'لا فحصَ دفعٍ على القراءةِ الطازجةِ داخلَ المعاملة');
      expect(write, greaterThan(-1));
      expect(check, lessThan(write),
          reason: 'فحصٌ بعدَ الكتابةِ لا يَمنعُ شيئاً — الترتيبُ هو الإصلاح');
    });

    test('(ه) والمنفِّذونَ الأربعةُ الباقونَ ما زالوا على القاعدة', () {
      // شواهدُ التعليل: زوالُ أيٍّ منها يُراجِعُ هذا الفحصَ لا يُسكِتُه.
      final String written = stripComments(exportBody(idx, 'onOrderWritten'));
      // **الشرطُ المشدودُ هو الذي يَحرُسُ فرعَ الإسنادِ بعينِه، لا أيُّ
      // ورودٍ للاسم.** `paidFlipped` يَرِدُ مرّتَين في هذا المُشغّل — الثانيةُ
      // لفرعِ «مدفوعٌ بلا موعدٍ ⇒ under_review»، وهو قرارٌ آخر — فاختبارُ
      // قضمٍ فكَّ شرطَ الفرعِ الأوّلِ ومرَّ **أخضرَ** على الثاني
      // («موضعٌ آخرُ يُرضي الفحصَ»، رابعَ مرّةٍ في هذا المستودع). فالمقياسُ
      // أقربُ `if (` قبلَ `_findFreeDriverForSlot` بموازنةِ أقواسِه.
      final int fi = written.indexOf('_findFreeDriverForSlot');
      expect(fi, greaterThan(-1),
          reason: 'فرعُ الإسنادِ الحدثيِّ لم يَعُد يُنادي المُسنِد');
      final int ifAt = written.lastIndexOf('if (', fi);
      expect(ifAt, greaterThan(-1));
      int d2 = 0;
      int endCond = -1;
      for (int k = ifAt + 3; k < written.length; k++) {
        if (written[k] == '(') d2++;
        if (written[k] == ')') {
          d2--;
          if (d2 == 0) {
            endCond = k;
            break;
          }
        }
      }
      expect(endCond, greaterThan(-1), reason: 'شرطٌ غيرُ متوازن');
      final String cond = written.substring(ifAt, endCond + 1);
      expect(cond.contains('paidFlipped'), isTrue,
          reason: 'فرعُ الإسنادِ الحدثيِّ لم يَعُد مشروطاً بانقلابِ الدفع — '
              'فيَصيرُ المُسنِدُ الآليُّ نفسُه يُسنِدُ غيرَ المدفوع');
      final String sweep =
          stripComments(exportBody(idx, 'sweepUnassignedPaidOrders'));
      expect(RegExp(r'is_paid\s*!==\s*true').allMatches(sweep).length, 2,
          reason: 'كتلتا المكنسةِ كانتا تتخطّيانِ غيرَ المدفوع');
      expect(capCode.contains('d.is_paid !== true'), isTrue,
          reason: 'عدُّ السعةِ لم يَعُد يتخطّى غيرَ المدفوع — '
              'فالنتيجةُ (ب) تُراجَع');
      final String stale =
          stripComments(exportBody(idx, 'cancelStaleUnpaidOrders'));
      expect(stale.contains('"status", "==", "pending"'), isTrue,
          reason: 'مكنسةُ الإلغاءِ لم تَعُد محصورةً بـpending — '
              'فالنتيجةُ (أ) تُراجَع');
    });

    test('(و) وضِلعا النتيجتَين (أ) و(ب) قائمان', () {
      // `scheduled` يَشغلُ السائقَ في فحوصِ التعارض...
      expect(
          RegExp(r'CONFLICT_STATUSES\s*=\s*\[[^\]]*"scheduled"')
              .hasMatch(stripComments(slotsSrc)),
          isTrue,
          reason: 'scheduled خرجَ من CONFLICT_STATUSES — يُراجَعُ التعليل');
      // ...ولا يُلغى بمكنسةِ الإلغاءِ لأنّها على pending وحدَها (ه أعلاه)،
      // وشرطُ التذكيرِ يَكفيه driverAssigned.
      final String remind = stripComments(
          exportBody(idx, 'remindClientsUpcomingAppointments'));
      expect(remind.contains('is_paid === true || driverAssigned'), isTrue,
          reason: 'شرطُ التذكيرِ تغيّرَ — تُراجَعُ النتيجةُ (ج)');
    });

    test('(ز) والسطحانِ يُنادِيانِ القاعدةَ قبلَ النداءِ الخادميّ', () {
      final String scrCode = stripComments(scr);
      expect(RegExp(r'\borderPaidForDispatch\s*\(').hasMatch(scrCode), isTrue,
          reason: 'شاشةُ تفاصيلِ الطلبِ لا تُنادي القاعدة');
      final int gate = scrCode.indexOf('orderPaidForDispatch(');
      final int call = scrCode.indexOf("httpsCallable('approveAndAssignOrder')");
      expect(call, greaterThan(-1));
      expect(gate, lessThan(call),
          reason: 'فحصٌ بعدَ النداءِ لا يَمنعُ شيئاً');
      expect(scrCode.contains('kUnpaidDispatchRefusal'), isTrue,
          reason: 'الشاشةُ تَكتبُ صياغةً ثانيةً للقرارِ نفسِه');

      final String panelCode = stripComments(panel);
      expect(RegExp(r'\borderPaidForDispatch\s*\(').hasMatch(panelCode), isTrue,
          reason: 'لوحةُ الويبِ لا تُنادي القاعدة');
      expect(panelCode.contains('UNPAID_DISPATCH_REFUSAL'), isTrue,
          reason: 'اللوحةُ تَكتبُ صياغةً ثانيةً للقرارِ نفسِه');
      // والزرُّ مشروطٌ بها — لا يُعرَضُ ثمّ يُرفَض.
      expect(
          RegExp(r'orderPaidForDispatch\(order\.is_paid\)\s*&&\s*\(\s*<button')
              .hasMatch(panelCode),
          isTrue,
          reason: 'زرُّ «تعيين سائق» غيرُ مشروطٍ بالدفعِ — زرٌّ مصيرُه الرفضُ فخّ');
      expect(panelCode.contains('!orderPaidForDispatch(order.is_paid)'), isTrue,
          reason: 'السببُ لا يُعرَضُ مكانَ الزرِّ — الإخفاءُ وحدَه '
              'يُقرأُ عطلاً في الشاشة');
    });

    test('(ط) والبوّابةُ الحاملةُ في مَوضعِ الكتابةِ نفسِه، قبلَ `tx.update`', () {
      // `_assignDriverScheduled` هي المعاملةُ **الوحيدةُ** التي تَكتبُ الإسناد،
      // فالقاعدةُ فيها تُغطّي كلَّ مُنادٍ — حاضراً ومستقبلاً. وكانت غائبةً
      // عنها: فحوصُها كانت `driver_id` والحالةَ وحدَهما.
      final int i = idx.indexOf('async function _assignDriverScheduled');
      expect(i, greaterThan(-1));
      final int open = idx.indexOf('{', i);
      int depth = 0;
      int end = -1;
      for (int k = open; k < idx.length; k++) {
        if (idx[k] == '{') depth++;
        if (idx[k] == '}') {
          depth--;
          if (depth == 0) {
            end = k;
            break;
          }
        }
      }
      expect(end, greaterThan(-1), reason: 'جسمٌ غيرُ متوازن');
      final String fn = stripComments(idx.substring(open, end + 1));
      final int gate = fn.indexOf('cur.is_paid !== true');
      final int write = fn.indexOf('tx.update(orderRef');
      expect(gate, greaterThan(-1),
          reason: 'بوّابةُ الدفعِ زالت من مَوضعِ الكتابةِ — فكلُّ مُنادٍ '
              'يَلزمُه فحصُه بنفسِه، وهو ما فتحَ الثغرةَ أوّلاً');
      expect(write, greaterThan(-1));
      expect(gate, lessThan(write),
          reason: 'فحصٌ بعدَ الكتابةِ لا يَمنعُ شيئاً');
      // والقراءةُ من اللقطةِ الطازجةِ داخلَ المعاملةِ لا من الوسائط.
      expect(fn.contains('const cur = snap.data()'), isTrue,
          reason: 'الفحصُ يَقرأُ قيمةً غيرَ طازجةٍ — فيَصيرُ سباقاً');
    });

    test('(ي) والنداءُ العميليُّ يَرفضُ مبكّراً برمزِه الخاصّ', () {
      // `autoAssignDriverDirectly` هو المسارُ العميليُّ الوحيدُ إلى الإسناد:
      // فحصُ المِلكيّةِ فيه يَشترطُ `_assertAdmin` **للغيرِ وحدَه**، فمالكُ
      // الطلبِ يَمُرّ. والرفضُ المبكّرُ لازمٌ ولو كانت البوّابةُ الحاملةُ
      // أدناه، لأنّ `false` من المعاملةِ يُترجَمُ إلى `"already_assigned"` —
      // كذبٌ يَحجبُ السببَ عن أيِّ تشخيصٍ لاحق.
      final String b = stripComments(exportBody(idx, 'autoAssignDriverDirectly'));
      expect(b.contains('orderData.is_paid !== true'), isTrue,
          reason: 'النداءُ العميليُّ بلا فحصِ دفع');
      expect(b.contains('"unpaid_order"'), isTrue,
          reason: 'الرفضُ يُعادُ برمزٍ خاصٍّ لا بـalready_assigned');
      final int paid = b.indexOf('orderData.is_paid !== true');
      final int assign = b.indexOf('_assignDriverScheduled(');
      expect(assign, greaterThan(-1));
      expect(paid, lessThan(assign), reason: 'الرفضُ بعدَ الإسنادِ لا يَمنعُه');
      // والمِلكيّةُ ما زالت مشروطةً كما كانت (مالكٌ أو أدمن) — شاهدُ التعليل.
      expect(b.contains('orderData.client_id !== request.auth.uid'), isTrue,
          reason: 'شرطُ «مالكٌ أو أدمن» تغيّرَ — يُراجَعُ التعليل');
    });

    test('(ك) ومجموعةُ مُنادِي مَوضعِ الكتابةِ كاملةً مُشتَقّةٌ ومُعلَّلة', () {
      // سبعةُ مُنادٍ، وستٌّ منهم كانوا يَفحصونَ الدفعَ قبلَ النداءِ والسابعُ
      // لا. فالمجموعةُ تُشَدُّ كاملةً: ثامنٌ يُراجَعُ بدلَ أن يُفتَرَضَ أنّ
      // بوّابةَ الكتابةِ تَكفيه (تَكفيه فعلاً — لكنّ مُنادياً جديداً قد
      // يَبني على `assigned: false` معنًى خاطئاً، كما بنى هذا على
      // «already_assigned»).
      final String code = stripComments(idx);
      final int defAt = code.indexOf('async function _assignDriverScheduled');
      expect(defAt, greaterThan(-1));
      // التعريفُ نفسُه يُطابقُ النمطَ (`async function _assignDriverScheduled(db,`)
      // فيُستبعَدُ بموضعِه لا بقائمةِ أسماء.
      final List<int> calls = RegExp(r'_assignDriverScheduled\(\s*db')
          .allMatches(code)
          .map((m) => m.start)
          .where((at) => at != defAt + 'async function '.length)
          .toList();
      expect(calls.length, 7,
          reason: 'عددُ مُنادِي مَوضعِ الكتابةِ تغيّرَ (${calls.length}) — '
              'راجِعْ الجديدَ: أهو على طلبٍ مدفوعٍ بالبناء؟');
      // ولكلٍّ اسمُ الدالّةِ المُحيطةِ، فالتعليلُ مقروء.
      final Set<String> owners = <String>{};
      for (final at in calls) {
        final String pre = code.substring(0, at);
        final int e = pre.lastIndexOf('\nexports.');
        final int f = pre.lastIndexOf('\nasync function ');
        final int anchorAt = e > f ? e : f;
        expect(anchorAt, greaterThan(-1));
        final RegExpMatch? nm =
            RegExp(r'^\n(?:exports\.|async function )(\w+)')
                .firstMatch(code.substring(anchorAt));
        expect(nm, isNotNull);
        owners.add(nm!.group(1)!);
      }
      expect(
          owners,
          {
            // انقلابُ `is_paid` (مرّتان: الفورُ وإعادةُ المحاولةِ عند التحرُّر)
            'onOrderWritten',
            // `is_paid !== true` مُرشَّحٌ قبلَ النداء
            'sweepUnassignedPaidOrders',
            // بعدَ `_tamaraFlipPaid` المُنتظَر
            'confirmPendingTamaraOrders',
            // مولِّدا زياراتِ العقد: المستندُ يُنشَأُ `is_paid: true`
            // (والثاني مشروطٌ بعقدٍ `active`، ولا يَصيرُ كذلك إلّا بالدفع)
            '_generateContractVisits',
            'generateSubscriptionVisits',
            // **المسارُ العميليّ** — وهو الذي كان بلا فحصٍ إطلاقاً
            'autoAssignDriverDirectly',
          },
          reason: 'مُنادٍ جديدٌ لمَوضعِ كتابةِ الإسناد — يُراجَعُ بوعي');
    });

    test('(ح) ومجموعةُ مُنادِي الإسنادِ كاملةً هي السطحانِ وحدَهما', () {
      final Set<String> callers = <String>{};
      for (final f in [
        ...sourcesIn('lib', atLeast: 120),
        ...sourcesIn('admin_panel/src',
            exts: const ['.ts', '.tsx'], atLeast: 20),
      ]) {
        final String code = stripComments(f.readAsStringSync());
        if (RegExp(r"""['"]approveAndAssignOrder['"]""").hasMatch(code)) {
          callers.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(
          callers,
          {
            'lib/screens/admin/admin_order_details_screen.dart',
            'admin_panel/src/pages/Orders.tsx',
          },
          reason: 'سطحٌ ثالثٌ يُنادي الإسنادَ — يَلزمُه نفسُ البوّابةِ '
              '(الخادمُ يَرفضُ، لكنّ زرّاً مصيرُه الرفضُ فخّ)');
    });
  });
}
