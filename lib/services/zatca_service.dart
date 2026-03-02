import 'dart:convert';
import 'dart:typed_data';

/// خدمة توليد بيانات الفاتورة الإلكترونية المتوافقة مع ZATCA (المرحلة الأولى)
/// مطور لـ: مؤسسة معاذ يحي محمد المالكي
class ZatcaService {
  
  /// تحويل بيانات الفاتورة إلى تنسيق Base64 TLV المطلوب في الـ QR Code
  /// هذا التنسيق هو الإلزامي للمرحلة الأولى من الفوترة الإلكترونية في السعودية
  static String generateZatcaQrCode({
    required String merchantName,
    required String vatNumber,
    required DateTime timestamp,
    required double totalAmount,
    required double vatAmount,
  }) {
    BytesBuilder builder = BytesBuilder();

    // Tag 1: اسم المورد (Merchant Name)
    builder.add(_encodeTlv(1, merchantName));
    // Tag 2: الرقم الضريبي (VAT Number)
    builder.add(_encodeTlv(2, vatNumber));
    // Tag 3: الختم الزمني (Timestamp)
    builder.add(_encodeTlv(3, timestamp.toIso8601String()));
    // Tag 4: إجمالي الفاتورة مع الضريبة (Total Amount)
    builder.add(_encodeTlv(4, totalAmount.toStringAsFixed(2)));
    // Tag 5: مبلغ ضريبة القيمة المضافة (VAT Amount)
    builder.add(_encodeTlv(5, vatAmount.toStringAsFixed(2)));

    return base64Encode(builder.toBytes());
  }

  /// ترميز البيانات بنظام (Tag-Length-Value)
  static Uint8List _encodeTlv(int tag, String value) {
    List<int> valueBytes = utf8.encode(value);
    return Uint8List.fromList([tag, valueBytes.length, ...valueBytes]);
  }
}
