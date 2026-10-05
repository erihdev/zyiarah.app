import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **طلبٌ بلا دفعٍ لا يُسنَد، ولا يُعدّ، ويُلغى بعد ثلاثين دقيقة.**
///
/// شاشةُ الملخّصِ كانت تَحملُ فرعاً لطريقةِ دفعٍ اسمُها `'subscription'`
/// يُنشئ طلباً مجّانيّاً (`isFree: true` ⇒ `amount: 0`, `is_paid: false`).
/// و`_selectedPaymentMethod` **لا يُضبَط إليه من أيِّ موضع** — الخياراتُ
/// المعروضةُ `card`/`tamara`/`stc_pay`/`wallet` فقط، وApple/Google Pay
/// تُنادي المُعالِجَ بأنفسِها — فكان ميتاً، ولم يَرَه أحد: `no_dead_code_test`
/// يَفحصُ `lib/services/` و`lib/utils/` **لا الشاشات**.
///
/// ولو وُصل يوماً لكان عطلاً صامتاً مركَّباً، لأنّ أربعةَ مسارٍ خادميٍّ تَشترط
/// الدفع:
///
///   `onOrderWritten` ............. الإسنادُ مشروطٌ بانقلابِ `is_paid`
///                                 (`paidFlipped`) ⇒ **لا سائقَ أبداً**.
///   `capacity.countBookings` ..... تَشترط `is_paid !== true ⇒ continue`
///                                 ⇒ لا يَستهلكُ سعةً، فيُباع اليومُ مرّتَين.
///   `remindClientsUpcoming...` ... تَشترط `is_paid === true` أو سائقاً مُسنَداً
///                                 ⇒ لا تذكير.
///   `cancelStaleUnpaidOrders` .... تَستثني تمارا/تابي وما يَحملُ معرّفَ دفعةِ
///                                 ميسر فقط ⇒ **يُلغى بعد ثلاثين دقيقة**
///                                 بـ`unpaid_expired`.
///
/// وزياراتُ الاشتراكِ الحقيقيّةُ لا تَمرُّ من الشاشةِ أصلاً:
/// `activateContractOnPaid` يُولّدها خادميّاً بـ`is_paid: true`، فتُسنَد وتُعدّ
/// وتُذكَّر كأيِّ طلبٍ مدفوع. فالحذفُ هو الصواب، لا الوصل.
///
/// هذا الملفُّ يَحرسُ الحذفَ **وسببَه**: لو عاد مسارُ طلبٍ مجّانيٍّ يوماً،
/// فالشروطُ الأربعةُ أعلاه هي ما يجب أن يُراجَع معه.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  group('الفرعُ المجّانيُّ حُذف', () {
    final screen = stripLineComments(read('lib/screens/payment_summary_screen.dart'));

    test('لا طريقةَ دفعٍ اسمُها subscription في الشاشة', () {
      expect(screen.contains("== 'subscription'"), isFalse,
          reason: 'الفرعُ الميتُ عاد — راجِع الشروطَ الأربعةَ في رأسِ هذا الملفّ');
      expect(screen.contains("'subscription', isFree"), isFalse);
    });

    test('ولا معامِلَ isFree', () {
      expect(screen.contains('isFree'), isFalse,
          reason: 'معامِلٌ كان `false` دائماً بعد حذفِ فرعِه الوحيد');
    });

    test('والتعليقُ الذي يَحملُ السببَ باقٍ', () {
      // بلا هذا التعليقِ يَبدو الحذفُ تنظيفاً عابراً، فيُعاد وصلُ المسارِ
      // بحسنِ نيّةٍ ويَعودُ العطل.
      final raw = read('lib/screens/payment_summary_screen.dart');
      expect(raw, contains('onOrderWritten'));
      expect(raw, contains('cancelStaleUnpaidOrders'));
      expect(raw, contains('activateContractOnPaid'));
    });
  });

  group('الشروطُ الأربعةُ التي تَجعلُ الطلبَ المجّانيَّ عطلاً', () {
    final idx = stripLineComments(read('functions/index.js'));
    final cap = stripLineComments(read('functions/capacity.js'));

    test('الإسنادُ مشروطٌ بانقلابِ is_paid', () {
      expect(idx, contains('const paidFlipped ='));
      expect(idx, contains('afterData.is_paid === true'));
      expect(idx, contains('if (paidFlipped && !afterData.driver_id &&'),
          reason: 'شرطُ الإسنادِ تغيّر — أعِد تقييمَ الطلبِ المجّانيّ معه');
    });

    test('السعةُ تَتجاهلُ غيرَ المدفوع', () {
      expect(cap, contains('if (d.is_paid !== true) continue;'),
          reason: 'لو صارت تَعدُّ غيرَ المدفوعِ فالسببُ الثاني سقط — راجِع');
    });

    test('التذكيرُ يَشترطُ دفعاً أو سائقاً', () {
      expect(idx, contains('d.is_paid === true || driverAssigned'));
    });

    test('مكنسةُ غيرِ المدفوعِ تَستثني تمارا/تابي ومعرّفَ ميسر فقط', () {
      final i = idx.indexOf('exports.cancelStaleUnpaidOrders');
      expect(i, greaterThan(0));
      final body = idx.substring(i, idx.indexOf('\nexports.', i + 10));
      expect(body, contains('if (d.is_paid === true) continue;'));
      expect(body, contains('["tamara", "tabby"].includes(d.payment_method)'));
      expect(body, contains('if (d.moyasar_payment_id) continue;'));
      // لا استثناءَ للاشتراك — وهذا هو السببُ الرابع. لو أُضيف يوماً فليكن
      // بوعي، لا كترقيعٍ لطلبٍ مجّانيٍّ أعيد وصلُه.
      expect(body.contains('subscription'), isFalse,
          reason: 'استثناءُ الاشتراكِ من المكنسةِ يُخفي العطلَ ولا يُصلحه: '
              'الطلبُ يبقى بلا سائقٍ وبلا عدٍّ في السعة');
    });

    test('وزياراتُ العقدِ تُولَّد مدفوعةً — وهي المسارُ الصحيح', () {
      expect(idx, contains('is_paid: true,'));
      expect(idx, contains('payment_method: "subscription",'),
          reason: 'توليدُ زياراتِ العقدِ خادميّاً هو ما يُغني عن أيِّ طلبٍ مجّانيّ');
    });
  });
}
