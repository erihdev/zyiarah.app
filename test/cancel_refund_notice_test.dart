import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/cancel_refund_notice.dart';

String _read(String p) => File(p).readAsStringSync();

/// يَحجبُ أسطرَ التعليقِ بمسافاتٍ كي تَبقى الإزاحاتُ، ثمّ يُقابَلُ بالخامِّ.
String _code(String src) => src
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');

void main() {
  group('نتيجةُ الإلغاءِ ثلاثُ حالاتٍ لا حالةٌ واحدة', () {
    test('(أ) غيرُ مدفوعٍ ⇒ لا جملةَ مالٍ إطلاقاً', () {
      final n = cancelRefundNotice(
          isPaid: false, paymentMethod: 'moyasar', amount: 230.0);
      expect(n.kind, CancelRefundKind.nothingPaid);
      expect(cancelRefundNoticeText(n), '');
      expect(cancelRefundAdminText(n), '');
    });

    test('(ب) زيارةُ اشتراكٍ ⇒ لا مبلغ، والزيارةُ تَبقى في الرصيد', () {
      final n = cancelRefundNotice(
          isPaid: true, paymentMethod: 'subscription', amount: 400.0);
      expect(n.kind, CancelRefundKind.subscriptionVisit);
      expect(n.amount, isNull, reason: 'لا رقمَ في حالةٍ لا مبلغَ فيها');
      final t = cancelRefundNoticeText(n);
      expect(t, contains('باقتكِ'));
      expect(t.contains('400'), isFalse,
          reason: 'ذكرُ مبلغٍ هنا وعدٌ بما لا يَحدث');
      // والجملةُ لا تَعِدُ بإيداعٍ ولا بمحفظة.
      expect(t.contains('محفظة'), isFalse);
    });

    test('(ج) مدفوعٌ بغيرِ الاشتراكِ ⇒ محفظةٌ لا بطاقة، بالرقم', () {
      for (final m in ['moyasar', 'tamara', 'wallet', 'stc_pay', null]) {
        final n =
            cancelRefundNotice(isPaid: true, paymentMethod: m, amount: 230.0);
        expect(n.kind, CancelRefundKind.walletCredit, reason: 'method=$m');
        expect(n.amount, 230.0);
        final t = cancelRefundNoticeText(n);
        expect(t, contains('230.00'));
        expect(t, contains('محفظة'));
        expect(t, contains('بطاقتكِ'),
            reason: 'الفرقُ بين المحفظةِ والبطاقةِ هو جوهرُ ما تَجهله');
      }
    });

    test('(د) مدفوعٌ بلا مبلغٍ معروف ⇒ جملةٌ شرطيّةٌ بلا رقمٍ مُلفَّق', () {
      for (final a in [null, 0.0, -5.0]) {
        final n =
            cancelRefundNotice(isPaid: true, paymentMethod: 'moyasar', amount: a);
        expect(n.kind, CancelRefundKind.walletCredit, reason: 'amount=$a');
        expect(n.amount, isNull, reason: 'amount=$a');
        final t = cancelRefundNoticeText(n);
        expect(t, contains('إن كان'));
        expect(RegExp(r'\d').hasMatch(t), isFalse,
            reason: 'رقمٌ في حالةِ الجهلِ هو عائلةُ «تقييمك 4.9»');
        final at = cancelRefundAdminText(n);
        expect(RegExp(r'\d').hasMatch(at), isFalse);
      }
    });
  });

  group('القاعدةُ تُطابِقُ الخادمَ، ولا تُستنسَخُ في الشاشات', () {
    test('(ه) الخادمُ يَستثني الاشتراكَ من إيداعِ المحفظة', () {
      final idx = _read('functions/index.js');
      expect(_code(idx), contains('after.payment_method !== "subscription"'),
          reason: 'لو زالَ الاستثناءُ فحالةُ (ب) تَصيرُ كذباً وتُراجَع');
      expect(_code(idx), contains('after.needs_refund === true'));
    });

    test('(و) الخادمُ لا يَردُّ زيارةً لم تُستهلَك', () {
      final rw = _read('functions/rewards.js');
      expect(_code(rw), contains('skipped = "never_counted"'),
          reason: 'هذا ما يَجعلُ «تبقى الزيارةُ في رصيدِ باقتكِ» صحيحاً');
    });

    test('(ز) الإيداعُ في المحفظةِ لا في البطاقة، وبالمبلغِ كاملاً', () {
      final re = _read('functions/refund_engine.js');
      final c = _code(re);
      expect(c, contains('balance: FieldValue.increment(amount)'));
      expect(c, contains('type: "refund"'));
    });

    test('(ح) لا مسارَ سحبٍ نقديٍّ للمحفظةِ في أيِّ جهة', () {
      // جوهرُ الرسالة: الرصيدُ يُنفَقُ داخلَ التطبيقِ وحدَه. فلو ظُهر مسارُ
      // سحبٍ يوماً فالنصُّ يُراجَعُ لا يُسكَت.
      final idx = _code(_read('functions/index.js'));
      expect(RegExp(r'exports\.\w*[Ww]ithdraw').hasMatch(idx), isFalse);
    });

    test('(ط) الشاشتانِ تُناديانِ القاعدةَ ولا تُعيدانِ كتابتَها', () {
      for (final f in [
        'lib/screens/orders_list_screen.dart',
        'lib/screens/admin/admin_order_details_screen.dart',
      ]) {
        final c = _code(_read(f));
        expect(c, contains('cancelRefundNotice('), reason: f);
        // لا تعدادَ محلّيٌّ للاشتراكِ بجوارِ النداء — وهو ما يُنتجُ الانحراف.
        expect(c.contains("== 'subscription'"), isFalse, reason: f);
      }
      expect(_code(_read('lib/screens/orders_list_screen.dart')),
          contains('cancelRefundNoticeText('));
      expect(_code(_read('lib/screens/admin/admin_order_details_screen.dart')),
          contains('cancelRefundAdminText('));
    });

    test('(ي) النصُّ يَظهرُ فعلاً في حوارِ العميلةِ وحوارِ الإدارة', () {
      final cl = _code(_read('lib/screens/orders_list_screen.dart'));
      // مُشتَقٌّ قبلَ الحوارِ ومُلحَقٌ بمحتواه — لا مُحتسَبٌ ثمّ مُهمَل.
      expect(cl, contains(r'$moneyLine'));
      expect(cl, contains('لا يمكن التراجع عن هذا الإجراء.'));
      final ad = _code(_read('lib/screens/admin/admin_order_details_screen.dart'));
      expect(ad, contains('content: Text(line)'));
      expect(ad, contains('if (go != true || !mounted) return;'),
          reason: 'تراجُعُ الإدارةِ يَجبُ أن يُوقِفَ الحفظَ فعلاً');
    });

    test('(ك) حوارُ الإدارةِ قبلَ الكتابةِ لا بعدَها', () {
      final src = _code(_read('lib/screens/admin/admin_order_details_screen.dart'));
      final dlg = src.indexOf('cancelRefundAdminText(');
      final save = src.indexOf('setState(() => _isLoading = true);', dlg);
      final call = src.indexOf("cancelOrder(widget.orderId, cancelledBy: 'admin')");
      expect(dlg, greaterThan(-1));
      expect(save, greaterThan(dlg));
      expect(call, greaterThan(dlg),
          reason: 'تأكيدٌ بعدَ الإلغاءِ لا يَمنعُ شيئاً');
    });

    test('(ل) زرُّ إلغاءِ العميلةِ محصورٌ بما تُجيزه القواعد', () {
      // الحالاتُ الثلاثُ تُقاسُ على هذا النطاق: لو وُسّع لِما بعدَ الإسنادِ
      // فالقرارُ يَحتاجُ مراجعةً (الاستردادُ حينها قد يَكونُ بوّابيّاً).
      final cl = _code(_read('lib/screens/orders_list_screen.dart'));
      expect(cl, contains("['pending', 'awaiting_payment'].contains(status)"));
    });

    test('(م) زيارةُ الاشتراكِ تُولَدُ `pending` فالزرُّ يَظهرُ عليها', () {
      // لو تغيّرت حالةُ التوليدِ فحالةُ (ب) قد تَصيرُ غيرَ قابلةٍ للوصول،
      // وذاك يُراجَعُ لا يُسكَت.
      final idx = _code(_read('functions/index.js'));
      final at = idx.indexOf('payment_method: "subscription"');
      expect(at, greaterThan(-1));
      expect(idx.substring(at, at + 200), contains('status: "pending"'));
    });
  });
}
