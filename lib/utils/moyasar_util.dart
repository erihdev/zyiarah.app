import 'dart:convert';
import 'package:crypto/crypto.dart';

/// أدوات مساعدة لبوابة Moyasar.
class MoyasarUtil {
  /// تشترط Moyasar أن يكون `given_id` بصيغة UUID صالحة، بينما معرّفات مستندات
  /// Firestore ليست UUID. لذلك نشتقّ UUID **ثابتاً** (على نمط v5/SHA-1) من
  /// معرّف الطلب.
  ///
  /// كونه ثابتاً يضمن أن نفس الطلب يُنتج دائماً نفس `given_id`، فتُعيد Moyasar
  /// الدفعة الموجودة عند إعادة المحاولة بدل شحن البطاقة مرتين (منع الشحن المزدوج).
  static String givenIdFromOrder(String seed) {
    final bytes = sha1.convert(utf8.encode('zyiarah-moyasar:$seed')).bytes;
    final b = List<int>.from(bytes.take(16));
    // ضبط بتّات الإصدار (5) والمتغيّر (RFC 4122).
    b[6] = (b[6] & 0x0f) | 0x50;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = [
      for (var i = 0; i < 16; i++) b[i].toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20, 32)}';
  }
}
