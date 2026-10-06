import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/cancel_refund_notice.dart';

/// جدولُ الحالاتِ **مشتركٌ بين اللغتَين**: نسخةٌ بعينِها في
/// `admin_panel/src/utils/cancelRefundNotice.test.ts` بين العلامتَين نفسِهما،
/// وهذا الفحصُ يَقرأُ ذلك الملفَّ ويُقارِنُ الجدولَين `jsonDecode`اً — فحالةٌ
/// تُضافُ لجهةٍ دون الأخرى تَسقط. (والقراءةُ من هنا لا من TS: `node:fs` بلا
/// أنواعٍ تحتَ `tsconfig.app.json` فيَسقطُ `npm run build` — نمطُ
/// `buildGate`/`serviceMeta`.)
// ── CANCEL_REFUND_CASES_BEGIN ──
const String _casesJson = '''
[
  [{"isPaid": false}, "nothingPaid", null],
  [{"isPaid": false, "amount": 120}, "nothingPaid", null],
  [{"isPaid": false, "paymentMethod": "subscription"}, "nothingPaid", null],
  [{"isPaid": true, "paymentMethod": "subscription"}, "subscriptionVisit", null],
  [{"isPaid": true, "paymentMethod": "subscription", "amount": 0}, "subscriptionVisit", null],
  [{"isPaid": true, "paymentMethod": "moyasar", "amount": 120.5}, "walletCredit", 120.5],
  [{"isPaid": true, "paymentMethod": "tamara", "amount": 300}, "walletCredit", 300],
  [{"isPaid": true, "paymentMethod": "wallet", "amount": 75}, "walletCredit", 75],
  [{"isPaid": true, "paymentMethod": "moyasar", "amount": 0}, "walletCredit", null],
  [{"isPaid": true, "paymentMethod": "moyasar", "amount": -5}, "walletCredit", null],
  [{"isPaid": true, "paymentMethod": "moyasar"}, "walletCredit", null],
  [{"isPaid": true}, "walletCredit", null]
]
''';
// ── CANCEL_REFUND_CASES_END ──

const Map<String, CancelRefundKind> _kindByName = <String, CancelRefundKind>{
  'nothingPaid': CancelRefundKind.nothingPaid,
  'subscriptionVisit': CancelRefundKind.subscriptionVisit,
  'walletCredit': CancelRefundKind.walletCredit,
};

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

    test('(ط) كلُّ سطحٍ يَبدأُ إلغاءً يُنادي القاعدةَ — والنطاقُ مُشتَقّ', () {
      // **مُشتَقٌّ لا مكتوبٌ بيد.** القائمةُ اليدويّةُ هي بعينِها ما جعلَ
      // لوحةَ الويبِ تَكتبُ الإلغاءَ نفسَه بلا جملةٍ عن المالِ: سطحانِ من
      // ثلاثة. فالنطاقُ الآن: كلُّ ملفٍّ دارتيٍّ يُنادي `cancelOrder(`
      // (عدا الخدمةِ التي تُعرّفُها)، وكلُّ ملفٍّ في اللوحةِ يَكتبُ
      // `cancelled_by`.
      final dartSurfaces = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .where((p) => p != 'lib/services/order_service.dart')
          .where((p) => _code(_read(p)).contains('cancelOrder('))
          .toList()
        ..sort();
      final panelSurfaces = Directory('admin_panel/src/pages')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => _code(_read(p)).contains('cancelled_by'))
          .toList()
        ..sort();
      expect(dartSurfaces.length, 2,
          reason: 'سطحٌ دارتيٌّ ثالثٌ يَبدأُ إلغاءً — يُراجَع: $dartSurfaces');
      expect(panelSurfaces.length, 1,
          reason: 'سطحٌ ثانٍ في اللوحةِ يَكتبُ إلغاءً — يُراجَع: $panelSurfaces');
      for (final f in [...dartSurfaces, ...panelSurfaces]) {
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

  group('السطحُ الثالثُ: لوحةُ الويب', () {
    const String webTest = 'admin_panel/src/utils/cancelRefundNotice.test.ts';
    const String panel = 'admin_panel/src/pages/Orders.tsx';

    final cases = (jsonDecode(_casesJson) as List).cast<List<dynamic>>();

    test('(ن) القاعدةُ الدارتيّةُ تُطابقُ الجدولَ المشترَك', () {
      expect(cases.length, greaterThanOrEqualTo(10));
      expect(cases.map((c) => c[1] as String).toSet(), _kindByName.keys.toSet(),
          reason: 'حالةٌ من الثلاثِ بلا شاهدٍ في الجدول');
      for (final c in cases) {
        final m = Map<String, dynamic>.from(c[0] as Map);
        final got = cancelRefundNotice(
          isPaid: m['isPaid'] == true,
          paymentMethod: m['paymentMethod'] as String?,
          amount: (m['amount'] as num?)?.toDouble(),
        );
        expect(got.kind, _kindByName[c[1] as String], reason: '$m');
        expect(got.amount, (c[2] as num?)?.toDouble(), reason: '$m');
      }
    });

    test('(س) الجدولُ نفسُه في اللوحةِ حرفاً بحرف — مرآةٌ لا دعوى', () {
      final String web = _read(webTest);
      final int a = web.indexOf('CANCEL_REFUND_CASES_BEGIN');
      final int b = web.indexOf('CANCEL_REFUND_CASES_END');
      expect(a, greaterThan(0), reason: 'علامةُ البدايةِ غابت عن $webTest');
      expect(b, greaterThan(a), reason: 'علامةُ النهايةِ غابت');
      final String block = web.substring(a, b);
      // **من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس** — `indexOf('[')` يَلتقطُ
      // قوسَ تعليقِ النوعِ (`Row[]`)، وهو الفخُّ المسجَّلُ في `serviceMeta`.
      final int end = block.lastIndexOf(']');
      expect(end, greaterThan(0), reason: 'لا مصفوفةَ حالاتٍ بين العلامتَين');
      int depth = 0;
      int start = -1;
      for (int i = end; i >= 0; i--) {
        if (block[i] == ']') depth++;
        if (block[i] == '[') {
          depth--;
          if (depth == 0) {
            start = i;
            break;
          }
        }
      }
      expect(start, greaterThanOrEqualTo(0), reason: 'قوسٌ غيرُ مُوازَن');
      final webCases = jsonDecode(block.substring(start, end + 1)) as List;
      expect(jsonEncode(webCases), jsonEncode(cases),
          reason: 'جدولُ الحالاتِ انحرفَ بين اللغتَين');
    });

    test('(ع) الجملةُ تُشتَقُّ قبلَ الحوارِ، والحوارُ قبلَ الكتابة', () {
      final c = _code(_read(panel));
      final iNotice = c.indexOf('cancelRefundNotice(');
      final iText = c.indexOf('cancelRefundAdminText(');
      final iConfirm = c.indexOf('await confirm(', iNotice);
      final iWrite = c.indexOf('runTransaction(db', iNotice);
      expect(iNotice, greaterThan(0), reason: 'اللوحةُ لا تُنادي القاعدة');
      expect(iText, greaterThan(iNotice), reason: 'النصُّ لا يُشتَقّ');
      expect(iConfirm, greaterThan(iText),
          reason: 'الجملةُ مُحتسَبةٌ بعدَ الحوارِ — فلا تُقرَأ');
      expect(iWrite, greaterThan(iConfirm),
          reason: 'تأكيدٌ بعدَ الكتابةِ لا يَمنعُ شيئاً — الترتيبُ هو الإصلاح');
      // والنصُّ مُلحَقٌ بالسؤالِ فعلاً لا مُحتسَبٌ ثمّ مُهمَل.
      expect(c.contains(r'${head}'), isTrue,
          reason: 'الجملةُ لا تُلحَقُ بمحتوى الحوار');
    });

    test('(ف) المقدارُ يُمرَّرُ خامّاً لا نصّاً منسَّقاً', () {
      // `OrderRecord.amount` نصٌّ للعرضِ («120 ر.س»)، فتمريرُه يُنتجُ
      // `null` في كلِّ حالةٍ — جملةٌ شرطيّةٌ بلا رقمٍ أبداً، تدهورٌ صامت.
      final c = _code(_read(panel));
      expect(c, contains('amount: order.amount_raw'),
          reason: 'المقدارُ لا يُمرَّرُ خامّاً');
      expect(RegExp(r'amount_raw\?: number').hasMatch(c), isTrue,
          reason: 'الحقلُ الخامُّ غيرُ مُعلَنٍ على السجل');
      expect(c, contains("typeof (doc.data() as DocumentData).amount === 'number'"),
          reason: 'مستندٌ قديمٌ بنصٍّ يَجبُ أن يُقرأَ «غيرَ معروف» لا صفراً');
    });

    test('(ص) حوارُ اللوحةِ يَحترِمُ الأسطر — وإلّا انطبقت الجملةُ على السؤال', () {
      // **الصنفُ على الوَسمِ الذي يَحملُ النصَّ بعينِه، لا في الملفّ.**
      // أوّلُ صياغةٍ كانت `contains('whitespace-pre-line')` على الملفِّ
      // المحجوبِ — و`_code` تَحجبُ `//` لا `{/* … */}`، وتعليقي الجديدُ
      // يَذكرُ الصنفَ بالاسم: فمرَّ قضمٌ **حذفَ الصنفَ من الوَسمِ** أخضرَ.
      // رابعَ عشَرَ مرّةٍ لهذا الفخِّ في هذا المستودع، ومرّتانِ في هذا الملفّ.
      final raw = _read('admin_panel/src/components/Notification.tsx');
      final iMsg = raw.indexOf('{confirmState.message}');
      expect(iMsg, greaterThan(0), reason: 'نصُّ الحوارِ اختفى');
      final iTag = raw.lastIndexOf('<p ', iMsg);
      expect(iTag, greaterThan(0), reason: 'لا وَسمَ يَحملُ نصَّ الحوار');
      final tag = raw.substring(iTag, raw.indexOf('>', iTag));
      expect(tag.contains('whitespace-pre-line'), isTrue,
          reason: 'الجملةُ تَنطبِقُ على السؤالِ كتلةً فتَفقدُ بروزَها');
      expect(tag.contains('{'), isFalse,
          reason: 'الاقتطاعُ ابتلعَ ما بعدَ الوَسمِ فالفحصُ يَفقدُ دقّتَه');
    });

    test('(ق) الإحالةُ تَتبعُ قدرةَ السطحِ — لا بطاقةَ ميسر في اللوحة', () {
      final c = _code(_read(panel));
      // نصُّ الدارتِ الإداريُّ يُحيلُ إلى «بطاقةِ عمليّاتِ ميسر أدناه» وهي
      // ليست هنا؛ فاللوحةُ تُمرّرُ قدرتَها الحقيقيّةَ (زرُّ التقسيط).
      expect(c, contains('bnplRefundHere: canBnplRefund(order)'),
          reason: 'الإحالةُ لا تَتبعُ قدرةَ السطح');
      final webRaw = _read('admin_panel/src/utils/cancelRefundNotice.ts');
      final web = _code(webRaw);
      expect(web.contains('بطاقة عمليات ميسر في تطبيق الإدارة'), isTrue,
          reason: 'إحالةُ البطاقةِ لا تَقولُ أين هي');
      // **الحجبُ ثمّ المضادّة.** رأسُ الوحدةِ يَقتبسُ نصَّ الدارتِ («بطاقةِ
      // عمليّاتِ ميسر **أدناه**») لِيُبيّنَ الفرق، فسقطَ هذا الفحصُ على
      // توثيقِه نفسِه — ثالثَ عشَرَ مرّةٍ في هذا المستودع.
      expect(web.contains('أدناه'), isFalse,
          reason: 'نصُّ اللوحةِ يُحيلُ إلى شيءٍ ليس فيها');
      expect(webRaw.contains('أدناه'), isTrue,
          reason: 'شرحُ الفرقِ زال — فلا يَعرفُ قارئٌ لِمَ اختلفَ النصّان');
    });
  });
}
