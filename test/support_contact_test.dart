// حارس: رقم الدعم في اللوحة يُخزَّن بعلامات اتجاه ومسافات («‭+966 53 048 9016‬»)
// فكان رابط واتساب/الهاتف يُشفَّر إلى %E2%80%AD… ويُرفض. التنقية إلزامية.
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:zyiarah/widgets/support_fab.dart';

void main() {
  group('supportContactDigits', () {
    const live = '‭+966 53 048 9016‬';

    test('الهاتف: أرقام فقط مع + في البداية', () {
      expect(supportContactDigits(live), '+966530489016');
      expect(Uri.parse('tel:${supportContactDigits(live)}').toString(),
          'tel:+966530489016');
    });

    test('واتساب: أرقام عارية بلا + (wa.me لا يقبل غيرها)', () {
      expect(supportContactDigits(live, forWhatsapp: true), '966530489016');
      expect(
          Uri.parse('https://wa.me/${supportContactDigits(live, forWhatsapp: true)}')
              .toString(),
          'https://wa.me/966530489016');
    });

    test('قيمة فارغة أو بلا أرقام → "" فلا يظهر زر ميت', () {
      expect(supportContactDigits(null), '');
      expect(supportContactDigits('  '), '');
      expect(supportContactDigits('‭‬'), '');
    });
  });

  group('ZyiarahMessagingService.cleanEmail', () {
    test('يُسقط U+200F والمسافات ويُصغّر — Resend كان يرفض non-ASCII', () {
      expect(ZyiarahMessagingService.cleanEmail('‏Omar.Ghamdi@Gmail.com '),
          'omar.ghamdi@gmail.com');
    });
  });
}
