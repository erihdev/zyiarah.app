import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

/// خدمة متوافقة مع متطلبات هيئة الزكاة والضريبة والجمارك (ZATCA)
/// تقوم بتوليد رمز الاستجابة السريعة (QR Code) بنظام التشفير (TLV) المطلوب قانونياً
class ZatcaService {
  // بيانات المنشأة — قيم افتراضية تُستخدم كـ fallback إن غاب إعداد النظام،
  // فلا تنكسر الفاتورة أبداً. تُحدَّث من system_configs/zatca_settings (E).
  static String merchantName = "مؤسسة معاذ يحي محمد المالكي";
  static String vatNumber = "310885360200003";
  static String crNumber = "7030376342";

  static bool _configLoaded = false;

  /// تحميل بيانات المنشأة من إعدادات النظام (يقرؤها أي مستخدم مسجَّل).
  /// تُستدعى قبل توليد الفاتورة. عند أي خطأ تبقى القيم الافتراضية.
  static Future<void> ensureConfigLoaded() async {
    if (_configLoaded) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('system_configs')
          .doc('zatca_settings')
          .get();
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        final m = (d['merchant_name'] as String?)?.trim();
        final v = (d['vat_number'] as String?)?.trim();
        final c = (d['cr_number'] as String?)?.trim();
        if (m != null && m.isNotEmpty) merchantName = m;
        if (v != null && v.isNotEmpty) vatNumber = v;
        if (c != null && c.isNotEmpty) crNumber = c;
      }
      _configLoaded = true;
    } catch (_) {
      // تبقى القيم الافتراضية — الفاتورة لا تنكسر
    }
  }

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
    bytesBuilder.add(_encodeTlv(3, '${timestamp.toIso8601String().split('.').first}Z'));

    // Tag 4: Total Amount (المبلغ الإجمالي مع الضريبة)
    bytesBuilder.add(_encodeTlv(4, totalAmount.toStringAsFixed(2)));

    // Tag 5: VAT Amount (مبلغ ضريبة القيمة المضافة 15%)
    bytesBuilder.add(_encodeTlv(5, vatAmount.toStringAsFixed(2)));

    // التحويل إلى Base64 كما تطلبه الهيئة
    return base64.encode(bytesBuilder.toBytes());
  }

  /// دالة مساعدة لتشفير كل حقل بنظام Tag-Length-Value
  static Uint8List _encodeTlv(int tag, String value) {
    final valueBytes = utf8.encode(value);
    final tlv = BytesBuilder();
    
    tlv.addByte(tag); // T: Tag
    tlv.addByte(valueBytes.length); // L: Length
    tlv.add(valueBytes); // V: Value
    
    return tlv.toBytes();
  }
}
