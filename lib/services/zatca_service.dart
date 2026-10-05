import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/utils/error_report.dart';
import 'package:zyiarah/utils/net_timeout.dart';

/// خدمة متوافقة مع متطلبات هيئة الزكاة والضريبة والجمارك (ZATCA)
/// تقوم بتوليد رمز الاستجابة السريعة (QR Code) بنظام التشفير (TLV) المطلوب قانونياً
class ZatcaService {
  // بيانات المنشأة — قيم افتراضية تُستخدم كـ fallback إن غاب إعداد النظام،
  // فلا تنكسر الفاتورة أبداً.
  //
  // **كانت تُقرأُ من `system_configs/zatca_settings` — مستندٍ لا يَكتبُه
  // شيءٌ في المستودعِ كلِّه (2026-10-05).** ومحرّرُ الإعداداتِ في تطبيقِ
  // الإدارةِ يَكتبُ `merchant_name` و`vat_number` في
  // `system_configs/main_settings`، فما يَكتبُه المالكُ **لا يَقرؤه أحد**:
  // الاسمُ والرقمُ الضريبيُّ المطبوعانِ على كلِّ فاتورةٍ ضريبيّةٍ — وداخلَ
  // رمزِ QR منها — ثابتانِ في الشفرةِ لا يُغيّرُهما أيُّ سطحٍ إداريّ، والشاشةُ
  // تَعرضُهما حقلَين قابلَين للحفظ. وهي عائلةُ مفاتيحِ الإصدارِ بعينِها
  // (قارئٌ يُفضّلُ حقلاً لا كاتبَ له)، واقعةً على وثيقةِ ضريبة.
  //
  // اليومَ الافتراضاتُ مطابقةٌ للواقعِ فلا فاتورةَ خاطئةٌ بعد — والعطلُ
  // يَصيرُ حيّاً لحظةَ أن يُصحّحَ المالكُ اسماً أو رقماً.
  //
  // فالقراءةُ من `main_settings` (حيث يَكتبُ المحرّرانِ فعلاً)، ويَبقى
  // `zatca_settings` **احتياطاً ثانياً** لمستندٍ قد يكون أُنشئ بيدٍ في
  // الكونسول — نفسُ قرارِ احتياطِ `latest_build` ولنفسِ السبب: إصلاحُ
  // الكاتبِ وحدَه لا يَكفي حين تكونُ في الإنتاجِ مستنداتٌ قائمة.
  static String merchantName = "مؤسسة معاذ يحي محمد المالكي";
  static String vatNumber = "310885360200003";
  static String crNumber = "7030376342";

  static bool _configLoaded = false;

  /// المستندُ الذي يَكتبُه المحرّرانِ فعلاً، ثمّ احتياطٌ لمستندٍ قديم.
  static const List<String> configDocs = ['main_settings', 'zatca_settings'];

  /// تحميل بيانات المنشأة من إعدادات النظام (يقرؤها أي مستخدم مسجَّل).
  /// تُستدعى عند الإقلاع وقبل توليد الفاتورة. عند أي خطأ تبقى القيم
  /// الافتراضية، فالفاتورة لا تنكسر.
  static Future<void> ensureConfigLoaded() async {
    if (_configLoaded) return;
    try {
      // الأوّلُ يَفوزُ لكلِّ حقلٍ على حِدَة: `main_settings` هو ما يَحفظُه
      // المالكُ، و`zatca_settings` يُكمِلُ ما لا يَحمله (مثلاً `cr_number`
      // في مستندٍ أُنشئ بيدٍ قبل أن يَصيرَ للحقلِ محرّر).
      for (final id in configDocs) {
        final doc = await FirebaseFirestore.instance
            .collection('system_configs')
            .doc(id)
            .get()
            .timeout(kNetCallTimeout);
        if (!doc.exists || doc.data() == null) continue;
        final d = doc.data()!;
        final m = (d['merchant_name'] as String?)?.trim();
        final v = (d['vat_number'] as String?)?.trim();
        final c = (d['cr_number'] as String?)?.trim();
        if (m != null && m.isNotEmpty && !_gotMerchant) {
          merchantName = m;
          _gotMerchant = true;
        }
        if (v != null && v.isNotEmpty && !_gotVat) {
          vatNumber = v;
          _gotVat = true;
        }
        if (c != null && c.isNotEmpty && !_gotCr) {
          crNumber = c;
          _gotCr = true;
        }
      }
      _configLoaded = true;
    } catch (e, st) {
      // بياناتُ البائعِ على وثيقةٍ ضريبيّة: الصمتُ عن المستخدمةِ صحيحٌ
      // (الفاتورةُ تَصدرُ بالافتراضات) لكنّ الصمتَ عنّا ليس كذلك.
      reportSilent(e, st, reason: 'zatca_config_load_failed');
    }
  }

  static bool _gotMerchant = false;
  static bool _gotVat = false;
  static bool _gotCr = false;

  /// توليد رمز QR متوافق مع ZATCA للفواتير الإلكترونية (المرحلة الأولى والثانية)
  static String generateZatcaQrCode({
    required DateTime timestamp,
    required double totalAmount,
    required double vatAmount,
  }) {
    final bytesBuilder = BytesBuilder();

    // Tag 1: Merchant Name (اسم المنشأة)
    bytesBuilder.add(_encodeTlv(1, merchantName));

    // Tag 2: VAT Number (الرقم الضريبي للمنشأة)
    bytesBuilder.add(_encodeTlv(2, vatNumber));

    // Tag 3: Timestamp (وقت إصدار الفاتورة بصيغة ISO 8601)
    bytesBuilder.add(_encodeTlv(3, '${timestamp.toUtc().toIso8601String().split('.').first}Z'));

    // Tag 4: Total Amount (المبلغ الإجمالي مع الضريبة)
    bytesBuilder.add(_encodeTlv(4, totalAmount.toStringAsFixed(2)));

    // Tag 5: VAT Amount (مبلغ ضريبة القيمة المضافة 15%)
    bytesBuilder.add(_encodeTlv(5, vatAmount.toStringAsFixed(2)));

    // التحويل إلى Base64 كما تطلبه الهيئة
    return base64.encode(bytesBuilder.toBytes());
  }

  /// دالة مساعدة لتشفير كل حقل بنظام Tag-Length-Value
  static Uint8List _encodeTlv(int tag, String value) {
    var valueBytes = utf8.encode(value);
    // طول TLV بايت واحد (ZATCA المرحلة 1) — نحدّ القيمة بـ255 بايت كي لا يفيض العدّاد
    // (اسم تاجر طويل جداً كان ينتج QR فاسداً). القيم الفعلية أقصر بكثير.
    if (valueBytes.length > 255) {
      valueBytes = valueBytes.sublist(0, 255);
    }
    final tlv = BytesBuilder();

    tlv.addByte(tag); // T: Tag
    tlv.addByte(valueBytes.length); // L: Length
    tlv.add(valueBytes); // V: Value

    return tlv.toBytes();
  }
}
