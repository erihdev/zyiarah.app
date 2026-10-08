import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/utils/vat.dart';

/// **لحظةُ إصدارِ الفاتورة** — مصدرٌ واحدٌ لما كان يُحسَب في ستّةِ مواضع.
///
/// ═══ ما كان مكسوراً ═══
///
/// خمسةٌ من ستّةِ مواضعَ تبني رمزَ ZATCA كانت تُمرّر `timestamp: DateTime.now()`
/// — **لحظةَ توليدِ الملفّ**، لا لحظةَ إصدارِ الفاتورة. و`zyiarah_pdf_service`
/// كان يَطبعُ «التاريخ / Date» من `DateTime.now()` هو أيضاً. وفي المسارِ
/// السعيدِ الفرقُ ثوانٍ، لكنّ للفاتورةِ **مسارَي إعادةِ توليدٍ** مُنفَّذَين
/// (`invoice_pdf_status: 'retrying'`): زرُّ العميلةِ في شاشةِ النجاح، وزرُّ
/// الأدمنِ في سجلِّ الفواتير. فإعادةُ توليدِ فاتورةٍ فشلت قبل أيّام تَطبعُ
/// **تاريخَ اليوم** على فاتورةٍ ضريبيّةٍ مبسّطةٍ لطلبٍ دُفع قبل أيّام، ويَحملُ
/// رمزُها (Tag 3) التاريخَ الخاطئَ نفسَه.
///
/// وفي شاشةِ الأدمن كانت `InvoiceView` المحمِّلةُ للصفِّ **تَحملُ**
/// `issuedAt` الصحيحَ، والنداءُ يُمرّر `DateTime.now()` بجوارِها.
///
/// وأسوأُ من ذلك: `InvoiceView.qrData()` تُبني الرمزَ من `issuedAt`، وتعليقُها
/// يقول إنّه «الرمزُ **نفسُه** الذي يُطبع في PDF» — فبطاقةُ الشاشةِ ونسخةُ
/// PDF كانتا تَحملان **رمزَين مختلفَين** لفاتورةٍ واحدة، والتعليقُ يَنفي ذلك.
///
/// ═══ القاعدة ═══
///
/// `paid_at` ثمّ `created_at` ثمّ الآن — وهي قاعدةُ `InvoiceView` نفسُها،
/// نُقلت هنا كي يَسألها الطرفان بدل أن تُكتب مرّتَين.

/// لحظةُ إصدارِ الفاتورةِ من وثيقةِ الطلب.
DateTime invoiceIssuedAt(Map<String, dynamic> data, {DateTime? now}) {
  DateTime? toT(dynamic v) => v is Timestamp ? v.toDate() : null;
  return toT(data['paid_at']) ?? toT(data['created_at']) ?? now ?? DateTime.now();
}

/// البوّابةُ الوحيدةُ إلى `ZatcaService.generateZatcaQrCode` من `lib/`:
/// الضريبةُ تُستخرَج من الإجماليِّ الشاملِ دائماً (`vatInGross`)، واللحظةُ
/// تُمرَّر صريحةً — فلا موضعَ يستطيع تمريرَ `DateTime.now()` بالسهو.
/// `test/invoice_stamp_test.dart` يُثبّت أنّها البوّابةُ الوحيدة.
String invoiceQrFor({required DateTime issuedAt, required double total}) =>
    ZatcaService.generateZatcaQrCode(
      timestamp: issuedAt,
      totalAmount: total,
      vatAmount: vatInGross(total),
    );

/// ترتيبُ حقولِ المبلغِ — **نسخةٌ مطابقةٌ لـ`FIELD_ORDER` في
/// `functions/amounts.js`**، ومشدودةٌ بها.
///
/// المعتمَدُ إداريّاً، ثمّ السلّةُ، ثمّ سعرُ الباقةِ، ثمّ الأساسيّ.
const List<String> kInvoiceAmountFields = [
  'final_amount',
  'total_amount',
  'planPrice',
  'amount',
];

/// إجماليُّ الفاتورةِ من وثيقةِ الطلب — **شاملاً الضريبةَ** (فهو ما خُصم).
///
/// **والقاعدةُ هي قاعدةُ الخادمِ بعينِها، بقصد:** `expectedAmount` تَقرأُ
/// السلسلةَ نفسَها لتُقارِنَ بما وصلَ من البوّابة، فالرقمُ المطبوعُ على
/// الفاتورةِ يَصيرُ **بالبناءِ** هو الرقمُ الذي طُلِبَ من البوّابةِ أن
/// تَخصِمَه. و`??` لا `||`: صفرٌ صريحٌ قيمةٌ لا غياب.
///
/// ═══ ما كان مكسوراً ═══
///
/// كان `InvoiceView.fromOrder` يَقرأُ `data['amount']` وحدَه — و**مستندُ
/// `store_orders` لا يَحملُ `amount` إطلاقاً**: `store_service` يُنشئُه
/// بـ`total_amount`، والكُتّابُ الستّةُ بعدَه لا يَمَسّونَ إلّا الحالةَ
/// والدفعَ والمراجعة. فـ`0.0`، على **وثيقةٍ ضريبيّة**:
///
///   • بطاقةُ الفاتورةِ في شاشةِ نجاحِ المتجرِ تَطبعُ «الإجمالي الخاضع
///     للضريبة» و«ضريبة القيمة المضافة» والإجماليَّ **أصفاراً** — لطلبٍ
///     دفعَته العميلةُ للتوّ (البطاقةُ تُعرَضُ متى `isPaid`).
///   • و`qrData()` تُشفِّرُ Tag 4 و Tag 5 «0.00» بينما ملفُّ PDF وُلِّدَ من
///     `widget.total` الصحيح — **فاتورةٌ واحدةٌ برمزَين**، وهو العطلُ الذي
///     وُجدت `invoiceQrFor` لإلغائِه، عائداً من بابِ حقلٍ غائبٍ لا وسيطٍ
///     منسيّ. وتعليقُ `qrData()` يَنفي ذلك بنصِّه.
///   • وزرُّ «إعادة المحاولة» يَكتبُ الصفرَ في **الملفِّ نفسِه**:
///     `_retryInvoice` كان يَقرأُ `data['amount'] ?? 0` فيَرفعُ فاتورةً
///     بإجماليٍّ صفرٍ فوقَ الفاشلة.
///   • وسجلُّ الفواتيرِ الإداريُّ يَجلبُ `orders` **و`store_orders`** معاً،
///     فكلُّ صفِّ متجرٍ فيه صفرٌ ورمزُه صفر.
///
/// ومسارُ المالِ نفسُه كان سليماً، ويُقالُ بحدِّه: الخادمُ يُقارِنُ
/// بـ`total_amount` عبرَ السلسلةِ نفسِها، فالخصمُ صحيحٌ — المكسورُ هو العرضُ
/// والوثيقة.
double invoiceTotalOf(Map<String, dynamic>? data) {
  if (data == null) return 0;
  for (final f in kInvoiceAmountFields) {
    final Object? v = data[f];
    if (v == null) continue;
    return v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
  }
  return 0;
}
