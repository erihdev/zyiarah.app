import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// عنونة فاتورة ZATCA للاشتراك (العقود).
///
/// **سبب وجوده:** بعد نجاح دفع الاشتراك كانت الفاتورة الضريبية تُكتب على
/// contracts/{_pendingOrderId} — معرّف طلبٍ عشوائي لا مستند عقد به — فيفشل
/// تحديث invoice_pdf_url بصمت وتضيع فاتورة الاشتراك كلياً. الحارسة تثبت أن
/// كل مسار دفع اشتراك يعنون الفاتورة بمعرّف العقد الحقيقي، وأن شاشة العقود
/// تقرؤها من حيث تُكتب.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// الملف بلا أسطر التعليقات — كي لا يلتقط المسح شرحاً يذكر النمط القديم.
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  test('شاشة ملخص الدفع تعنون فاتورة العقد بمعرّف العقد لا _pendingOrderId', () {
    final s = codeOnly('lib/screens/payment_summary_screen.dart');
    expect(s, contains('bgInvoiceDocId = widget.contractId ?? id'),
        reason: 'مستند فاتورة الاشتراك يجب أن يكون contracts/{contractId}');
    expect(s, contains('orderId: bgInvoiceDocId'),
        reason: 'نداء generateAndUploadInvoice يجب أن يستخدم المعرّف المصحّح');
    expect(RegExp(r'generateAndUploadInvoice\(\s*orderId:\s*id,').hasMatch(s),
        isFalse,
        reason:
            'عودة النمط القديم (orderId: id مع collectionPath=contracts) تعيد ضياع الفاتورة');
  });

  test('مسار تمارا (checkout) يعنون فاتورة العقد بمعرّف العقد ومجموعته', () {
    final s = codeOnly('lib/screens/checkout_screen.dart');
    expect(s, contains('invoiceDocId = widget.contractId ?? newOrderId'),
        reason: 'فاتورة اشتراك تمارا يجب أن تُكتب على مستند العقد الحقيقي');
    expect(s, contains('collectionPath: invoiceCollection'),
        reason: 'المجموعة يجب أن تتبع نوع السجل (contracts للعقد، orders للطلب)');
    expect(
        RegExp(r"widget\.contractId != null \? 'contracts' : 'orders'")
            .hasMatch(s),
        isTrue,
        reason: 'اختيار المجموعة يجب أن يُشتق من وجود contractId');
  });

  test('مسار تمارا لا يقرأ orders/{id} لمستند معدوم في حالة العقد', () {
    // قراءة مستند طلب معدوم تُرفض من القواعد (resource=null) فتقتل الإغلاق
    // كاملاً قبل الفاتورة وشاشة النجاح — الكود يجب أن يشتق كود العقد من معرّفه.
    final s = codeOnly('lib/screens/checkout_screen.dart');
    expect(s, contains('orderCode = widget.contractId!'),
        reason: 'كود فاتورة الاشتراك هو معرّف العقد بلا قراءة orders معدومة');
  });

  test('شاشة عقود العميل تقرأ الفاتورة من حيث تُكتب (invoice_pdf_url)', () {
    final s = codeOnly('lib/screens/contracts_list_screen.dart');
    expect(s, contains('invoice_pdf_url'),
        reason: 'بلا قراءة invoice_pdf_url على بطاقة العقد لا مسار للعميلة لفاتورتها');
  });
}
