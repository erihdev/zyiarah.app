// حارس: رقم الدعم في اللوحة يُخزَّن بعلامات اتجاه ومسافات («+966 53 048 9016»)
// فكان رابط واتساب/الهاتف يُشفَّر إلى %E2%80%AD… ويُرفض. التنقية إلزامية.
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:zyiarah/utils/phone_format.dart';
import 'package:zyiarah/widgets/support_fab.dart';

void main() {
  group('supportContactDigits', () {
    // U+202D … U+202C كما تُخزَّن في اللوحة (بلا الحرفين الخامين في المصدر).
    final lro = String.fromCharCode(0x202D);
    final pdf = String.fromCharCode(0x202C);
    final live = '$lro+966 53 048 9016$pdf';

    test('الهاتف: أرقام فقط مع + في البداية', () {
      expect(supportContactDigits(live), '+966530489016');
      expect(Uri.parse('tel:${supportContactDigits(live)}').toString(),
          'tel:+966530489016');
    });

    test('واتساب صار شأنَ whatsappNumber وحدَها — وهي أقوى', () {
      // كان `forWhatsapp: true` يُسقط `+` فقط، فرقمُ دعمٍ محلّيٌّ يَخرج كما هو
      // و`wa.me` يَرفضه. `whatsappNumber` تُسقط غيرَ الأرقامِ (فتُغطّي علاماتَ
      // الاتجاهِ نفسَها) **وتُلحق 966 بالمحلّيّ**.
      expect(whatsappNumber(live), '966530489016');
      expect(Uri.parse('https://wa.me/${whatsappNumber(live)}').toString(),
          'https://wa.me/966530489016');
      // وهذا ما كانت الصيغةُ القديمةُ تُفسده:
      expect(whatsappNumber('0530489016'), '966530489016');
      expect(whatsappNumber('530489016'), '966530489016');
    });

    test('قيمة فارغة أو بلا أرقام → "" فلا يظهر زر ميت', () {
      expect(supportContactDigits(null), '');
      expect(supportContactDigits('  '), '');
      expect(supportContactDigits('$lro$pdf'), '');
    });
  });

  group('ZyiarahMessagingService.cleanEmail', () {
    test('يُسقط U+200F والمسافات ويُصغّر — Resend كان يرفض non-ASCII', () {
      expect(ZyiarahMessagingService.cleanEmail('‏Omar.Ghamdi@Gmail.com '),
          'omar.ghamdi@gmail.com');
    });
  });
}
