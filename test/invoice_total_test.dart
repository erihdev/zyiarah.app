import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/invoice_view.dart';
import 'package:zyiarah/utils/invoice_stamp.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **إجماليُّ الفاتورةِ كان حقلاً واحداً، ومستندُ المتجرِ لا يَحملُه.**
///
/// `store_orders` يُنشَأُ بـ`total_amount` ولا يَحملُ `amount` إطلاقاً، و
/// `InvoiceView.fromOrder` كانت تَقرأُ `data['amount']` وحدَه — فصفرٌ على
/// **وثيقةٍ ضريبيّة**: بطاقةُ شاشةِ النجاحِ، ورمزُ QR بـTag 4/5 أصفاراً بينما
/// ملفُّ PDF صحيحٌ (**فاتورةٌ واحدةٌ برمزَين**، وهو ما وُجدت `invoiceQrFor`
/// لإلغائه)، وزرُّ الإعادةِ يَكتبُ الصفرَ في الملفِّ نفسِه، وكلُّ صفِّ متجرٍ
/// في سجلِّ الفواتيرِ الإداريّ.
void main() {
  group('إجماليُّ الفاتورة', () {
    test('(أ) السلسلةُ سلوكاً — والصفرُ الصريحُ قيمةٌ لا غياب', () {
      expect(invoiceTotalOf({'amount': 115.0}), 115.0);
      // طلبُ المتجر: `total_amount` وحدَه.
      expect(invoiceTotalOf({'total_amount': 230.5}), 230.5);
      // العقد.
      expect(invoiceTotalOf({'planPrice': 1380.0}), 1380.0);
      // المعتمَدُ إداريّاً يَتقدّمُ السلّةَ (وهو تعليلُ الترتيبِ الخادميّ).
      expect(invoiceTotalOf({'final_amount': 200.0, 'total_amount': 300.0}),
          200.0);
      expect(invoiceTotalOf({'total_amount': 300.0, 'amount': 7.0}), 300.0);
      // `??` لا `||`: صفرٌ صريحٌ قرارٌ (طلبٌ مجّانيٌّ أو تسويةٌ كاملة).
      expect(invoiceTotalOf({'total_amount': 0, 'amount': 99.0}), 0.0);
      // نصٌّ رقميٌّ من مستندٍ قديم، وغيابٌ تامّ.
      expect(invoiceTotalOf({'amount': '115.5'}), 115.5);
      expect(invoiceTotalOf(const {}), 0.0);
      expect(invoiceTotalOf(null), 0.0);
    });

    test('(ب) الترتيبُ هو ترتيبُ الخادمِ حرفاً — فالمطبوعُ هو المُقارَنُ به',
        () {
      final js = File('functions/amounts.js').readAsStringSync();
      final m = RegExp(r'const FIELD_ORDER = \[([^\]]*)\]').firstMatch(js);
      expect(m, isNotNull, reason: 'ترتيبُ الخادمِ لم يُستخرَج — فحصٌ أجوف');
      final server = RegExp('"([A-Za-z_]+)"')
          .allMatches(m!.group(1)!)
          .map((x) => x.group(1)!)
          .toList();
      expect(server.length, greaterThanOrEqualTo(3));
      expect(kInvoiceAmountFields, server,
          reason: 'افترقَ ترتيبُ الفاتورةِ عن `expectedAmount` — فالرقمُ '
              'المطبوعُ لم يَعُدْ هو الرقمَ الذي قارَنَه الخادمُ بما خُصم');
    });

    test('(ج) بطاقةُ طلبِ المتجرِ لم تَعُدْ صفراً، واسمُها لم يَعُدْ «-»', () {
      final v = InvoiceView.fromOrder('ZY-1', {
        'total_amount': 230.0,
        'is_paid': true,
        'items': const [
          {'id': 'p1', 'name': 'منظّف', 'quantity': 2, 'price': 100.0},
        ],
      }, now: DateTime(2026, 10, 8));
      expect(v.total, 230.0);
      expect(v.vat, closeTo(30.0, 0.0001));
      expect(v.net, closeTo(200.0, 0.0001));
      expect(v.serviceName, 'طلب منتجات من المتجر',
          reason: 'البطاقةُ تَطبعُ «-» بينما الملفُّ يَطبعُ اسمَ المتجر');
      // والرمزُ ليس رمزَ صفرٍ: نفسُ لحظةٍ ونفسُ إجماليٍّ ⇒ نفسُ الرمز.
      expect(v.qrData(), invoiceQrFor(issuedAt: v.issuedAt, total: 230.0));
      expect(v.qrData() == invoiceQrFor(issuedAt: v.issuedAt, total: 0),
          isFalse);
      // وطلبُ الخدمةِ كما كان.
      final o = InvoiceView.fromOrder('ZY-2', {
        'amount': 115.0,
        'service_name': 'تنظيف منزلي',
        'is_paid': true,
      }, now: DateTime(2026, 10, 8));
      expect(o.total, 115.0);
      expect(o.serviceName, 'تنظيف منزلي');
    });

    test('(د) كلُّ قارئٍ لإجماليِّ الفاتورةِ يَمُرُّ بالقاعدة — نطاقٌ مُشتَقّ',
        () {
      /// قراءةٌ مُستثناةٌ، **ولكلٍّ سببُه**.
      const Map<String, String> allowed = {
        // القاعدةُ نفسُها.
        'lib/utils/invoice_stamp.dart': 'موضعُ القاعدة',
        // حِملُ الإنشاءِ: يَكتبُ المبلغَ ولا يَقرؤه من وثيقة.
        'lib/screens/payment_summary_screen.dart': 'كتابةٌ لا قراءة',
      };
      bool readsAmountField(String code) =>
          RegExp(r"""\['amount'\]|\["amount"\]""").hasMatch(code);

      // **والكاشفُ شفرةٌ تُختبَرُ كالشفرة.** دعوى هذا الفحصِ **سالبةٌ**
      // والمستودعُ نظيفٌ بعدَ الإصلاح، فنجاحُه وحدَه لا يُبرهِنُ أنّه يَرى
      // شيئاً — وقضمةٌ تُجوِّفُ النمطَ مرَّت خضراء. فيُشَدُّ على شكلٍ
      // مُصطنَعٍ يَحملُ المحظورَ، ونفيٍ لإيجابيّةٍ كاذبة.
      expect(readsAmountField("final x = data['amount'];"), isTrue);
      expect(readsAmountField('final x = data["amount"];'), isTrue);
      expect(readsAmountField("final x = data['total_amount'];"), isFalse);

      final offenders = <String>[];
      final feeders = <String>[];
      for (final f in sourcesIn('lib', atLeast: 100)) {
        final code = stripComments(f.readAsStringSync());
        // قراءةٌ تُغذّي فاتورةً: الملفُّ يُمرّرُ مبلغاً إلى بوّابةِ الرمزِ أو
        // مُولِّدِ PDF أو يَبني `InvoiceView`.
        final bool feedsInvoice = code.contains('invoiceQrFor(') ||
            code.contains('generateAndUploadInvoice(') ||
            code.contains('InvoiceView(');
        if (!feedsInvoice) continue;
        feeders.add(f.path);
        if (!readsAmountField(code)) continue;
        if (allowed.containsKey(f.path)) continue;
        offenders.add(f.path);
      }
      // وأرضيّةٌ على التعداد: مسحٌ يَنحلُّ إلى صفرِ ملفٍّ يُقرأُ «نظيفاً».
      expect(feeders.length, greaterThanOrEqualTo(4),
          reason: 'لم يُعَدَّ مُغذٍّ واحدٌ للفاتورة — فحصٌ أجوف');
      expect(offenders, isEmpty,
          reason: '\n\nملفٌّ يُغذّي فاتورةً من `[\'amount\']` مباشرةً:\n  • '
              '${offenders.join('\n  • ')}\n');
      // والقاعدةُ مُستعمَلةٌ فعلاً في الموضعَين اللذَين كانا مكسورَين.
      for (final p in const [
        'lib/models/invoice_view.dart',
        'lib/screens/order_success_screen.dart',
      ]) {
        expect(File(p).readAsStringSync().contains('invoiceTotalOf('), isTrue,
            reason: '$p لم يَعُدْ يُنادي القاعدة');
      }
    });

    test('(هـ) شاهدُ التعليل: لكلِّ مجموعةٍ حقلٌ تُغطّيه السلسلة', () {
      // **ما يَجعلُ السلسلةَ صحيحةً ليس منعَ `amount` عن مستندِ المتجرِ** —
      // لو أُضيفَ لَبقيَ `total_amount` متقدّماً فلا يَتغيّرُ شيء. الشرطُ
      // الحقيقيُّ أنّ **كلَّ مُنشئٍ يَكتبُ حقلاً تَعرفُه السلسلة**، وإلّا عادَ
      // الصفر. فهذا ما يُشَدُّ، مُقتطَعاً بموازنةِ الأقواسِ لا بنافذةِ أحرف
      // (مُنشئُ المتجرِ يَبعدُ عن اسمِ مجموعتِه ~٤٥ سطراً، وأوّلُ صياغةٍ
      // بنافذةِ ٤٠٠ محرفٍ مرَّت خضراءَ على قضمةٍ تُضيفُ الحقل).
      String payloadAfter(String src, String anchor) {
        final int i = src.indexOf(anchor);
        expect(i, greaterThan(-1), reason: 'المِرساةُ «$anchor» زالت');
        final int o = src.indexOf('{', i);
        int d = 0, j = o;
        while (j < src.length) {
          if (src[j] == '{') d++;
          if (src[j] == '}') {
            d--;
            if (d == 0) break;
          }
          j++;
        }
        return src.substring(o, j + 1);
      }

      final store = payloadAfter(
          File('lib/services/store_service.dart').readAsStringSync(),
          'transaction.set(docRef,');
      expect(store.contains("'total_amount':"), isTrue,
          reason: 'مُنشئُ طلبِ المتجرِ لا يَكتبُ حقلاً تَعرفُه السلسلة — '
              'فتُطبَعُ فاتورتُه صفراً مرّةً أخرى');
      expect(kInvoiceAmountFields.contains('total_amount'), isTrue);

      final order = payloadAfter(
          File('lib/screens/payment_summary_screen.dart').readAsStringSync(),
          'required double amount,');
      expect(order.contains("'amount':"), isTrue,
          reason: 'مُنشئُ طلبِ الخدمةِ لا يَكتبُ حقلاً تَعرفُه السلسلة');
      expect(kInvoiceAmountFields.contains('amount'), isTrue);

      final contract = payloadAfter(
          File('lib/screens/contract_signing_screen.dart').readAsStringSync(),
          'await docRef.set(');
      expect(contract.contains("'planPrice':"), isTrue,
          reason: 'مُنشئُ العقدِ لا يَكتبُ حقلاً تَعرفُه السلسلة');
      expect(kInvoiceAmountFields.contains('planPrice'), isTrue);
    });

    test('(و) سجلُّ الفواتيرِ الإداريُّ يَجلبُ المجموعتَين — فالصفرُ كان يَظهرُ له',
        () {
      final s = File('lib/screens/admin/admin_invoices_screen.dart')
          .readAsStringSync();
      expect(s.contains("fetch('store_orders')"), isTrue,
          reason: 'لم يَعُدْ يَجلبُ طلباتِ المتجرِ — يُراجَعُ التعليل');
      expect(s.contains("fetch('orders')"), isTrue);
      // وصفوفُه تُبنى من `InvoiceView.fromOrder` لا من قراءةٍ محلّيّة.
      expect(
          File('lib/models/invoice_log_entry.dart')
              .readAsStringSync()
              .contains('InvoiceView.fromOrder('),
          isTrue);
    });
  });
}
