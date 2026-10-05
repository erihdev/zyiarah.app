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
