import 'dart:convert';
import 'dart:typed_data';

/// خدمة متوافقة مع متطلبات هيئة الزكاة والضريبة والجمارك (ZATCA)
/// تقوم بتوليد رمز الاستجابة السريعة (QR Code) بنظام التشفير (TLV) المطلوب قانونياً
class ZatcaService {
  
  /// توليد رمز QR متوافق مع ZATCA للفواتير الإلكترونية (المرحلة الأولى والثانية)
  static String generateZatcaQrCode({
    String? merchantName,
    String? vatNumber,
    required DateTime timestamp,
    required double totalAmount,
    required double vatAmount,
  }) {
    // استخدام البيانات الممررة أو القيم الافتراضية للمؤسسة
    final String name = merchantName ?? "مؤسسة معاذ يحي محمد المالكي";
    final String vat = vatNumber ?? "310885360200003";

    final bytesBuilder = BytesBuilder();

    // Tag 1: Merchant Name (اسم المنشأة)
    bytesBuilder.add(_encodeTlv(1, name));

    // Tag 2: VAT Number (الرقم الضريبي للمنشأة)
    bytesBuilder.add(_encodeTlv(2, vat));

    // Tag 3: Timestamp (وقت إصدار الفاتورة بصيغة ISO 8601)
    bytesBuilder.add(_encodeTlv(3, timestamp.toIso8601String()));

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
