import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/phone_format.dart';

/// **رابطُ واتساب ميتٌ في كلِّ طلب، واتجاهٌ واحدٌ فقط كان يَعمل.**
///
/// `wa.me` لا يَقبل إلّا الصيغةَ الدولّيّةَ العارية. وحقلُ الجوّالِ في
/// التسجيلِ تلميحُه **`5XXXXXXXX`**، فالرقمُ المخزَّنُ على الطلبِ محلّيٌّ
/// (تسعةُ أرقامٍ تبدأ بـ5، أو عشرةٌ تبدأ بـ05).
///
/// و`whatsappNumber` مكتوبةٌ لهذا بعينه — ويُناديها **اتجاهٌ واحد**:
/// `order_tracking_screen` (العميلةُ ← السائق). أمّا الاتجاهُ المقابل، زرُّ
/// «واتساب» في `admin_order_details_screen`، فكان يَبني
/// `https://wa.me/$phone` خاماً ⇒ `wa.me/5XXXXXXXX` — **رابطٌ ميتٌ في كلِّ
/// طلبٍ تقريباً**. فاتجاهٌ يَعمل والآخرُ لا، والدالّةُ الصحيحةُ في الملفِّ
/// المجاور.
///
/// ومعه عطلٌ من العائلةِ نفسِها: `if (await canLaunchUrl(url))` **بلا `else`**
/// — فحين يتعذّر الفتحُ لا شيءَ يحدثُ ولا كلمةَ تُقال، فيظنُّ الأدمنُ الزرَّ
/// معطّلاً (نفسُ «زرٌّ يُضغط فلا يحدث شيء»).
///
/// وموضعان آخران **كامنان**: رقمُ الدعمِ في
/// `driver_profile_screen`/`driver_dashboard` يأتي من `support_whatsapp` الذي
/// يَكتبه الأدمنُ في الإعداداتِ **بلا تلميحِ صيغة** (افتراضُه دوليٌّ
/// `966500000000`) — فمن يَكتبه محلّيّاً يَقتل الرابطَين. التطبيعُ عند
/// القراءةِ يُغطّي الصيغتَين، وكلاهما كان يُبلّغ عند الفشلِ أصلاً.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  group('whatsappNumber', () {
    test('الصيغةُ المحلّيّةُ التي يُخزّنُها التسجيلُ فعلاً', () {
      // تلميحُ حقلِ التسجيل: 5XXXXXXXX
      expect(whatsappNumber('512345678'), '966512345678');
      expect(whatsappNumber('0512345678'), '966512345678');
      expect(whatsappNumber('05 1234 5678'), '966512345678');
      expect(whatsappNumber('٠٥١٢٣٤٥٦٧٨'), '',
          reason: 'أرقامٌ عربيّةٌ-هنديّةٌ ليست [0-9] — تُصفّى كلُّها فيبقى فراغ');
    });

    test('الدولّيّةُ تمرُّ كما هي، وبادئةُ 00 تُزال', () {
      expect(whatsappNumber('966512345678'), '966512345678');
      expect(whatsappNumber('00966512345678'), '966512345678');
      expect(whatsappNumber('+966 51 234 5678'), '966512345678');
    });

    test('الغيابُ غيابٌ — لا رقمٌ مُختلَق', () {
      for (final bad in [null, '', '   ', 'لا رقم', '+++']) {
        expect(whatsappNumber(bad), '', reason: '«$bad»');
      }
    });

    test('ما لا يُعرَف يمرُّ كما هو — لا تخريبَ لرقمٍ صحيحٍ غيرِ سعوديّ', () {
      // ثمانيةُ أرقامٍ أو رقمٌ أجنبيٌّ: لا نُلحقُ 966 بما ليس سعوديّاً.
      expect(whatsappNumber('12345678'), '12345678');
      expect(whatsappNumber('971501234567'), '971501234567');
      // وعشرةٌ لا تبدأ بـ05 لا تُقَصّ.
      expect(whatsappNumber('1234567890'), '1234567890');
    });

    test('ذهابٌ وعودة: التطبيعُ ثابتٌ عند التكرار', () {
      for (final raw in ['512345678', '0512345678', '00966512345678', '']) {
        final once = whatsappNumber(raw);
        expect(whatsappNumber(once), once, reason: 'raw=«$raw»');
      }
    });
  });

  group('حارسُ المصدر: كلُّ رابطِ wa.me يمرُّ بالدالّة', () {
    late List<String> builders;

    setUpAll(() {
      builders = [];
      for (final f in Directory('$repo/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final code = stripLineComments(f.readAsStringSync());
        if (code.contains('wa.me/')) {
          builders.add(f.path.substring(repo.length + 1));
        }
      }
      builders.sort();
    });

    test('مجموعةُ البُناةِ مُثبَّتة — خامسٌ يُراجَع بوعي', () {
      expect(builders, [
        'lib/screens/admin/admin_order_details_screen.dart',
        'lib/screens/driver_dashboard.dart',
        'lib/screens/driver_profile_screen.dart',
        'lib/screens/order_tracking_screen.dart',
        // الخامسُ: زرُّ الدعمِ العائم. كان له **مُنقٍّ ثانٍ** خاصٌّ به
        // (`supportContactDigits(forWhatsapp: true)`) يُسقط `+` فقط ولا
        // يُلحق 966 بالمحلّيّ — قاعدتان لسؤالٍ واحدٍ وإحداهما أضعف. صار
        // يمرُّ بالدالّةِ الواحدة، وبقي المُنقّي لرابطِ `tel:` وحدَه.
        'lib/widgets/support_fab.dart',
      ], reason: 'بانٍ جديدٌ لرابطِ واتساب — هل يُطبّع الرقم؟');
    });

    test('ولا واحدٌ منها يُدرج رقماً خاماً', () {
      for (final rel in builders) {
        final code = stripLineComments(read(rel));
        expect(code, contains('whatsappNumber('),
            reason: '$rel يَبني wa.me بلا تطبيع — رابطٌ ميتٌ لرقمٍ محلّيّ');
        // وكلُّ ما يُدرَج بعد `wa.me/` إمّا نداءٌ مباشرٌ للدالّة أو متغيّرٌ
        // **مُسنَدٌ منها في الملفِّ نفسِه** — إثباتُ الاشتقاقِ نصّيّاً أدقُّ
        // ما يُمكن، وبلا هذا الفحصِ يَكفي وجودُ النداءِ في أيِّ موضعٍ آخر.
        final interpolated = RegExp(r'wa\.me/\$\{?([A-Za-z_]\w*)')
            .allMatches(code)
            .map((m) => m.group(1)!)
            .toSet();
        for (final v in interpolated) {
          if (v == 'whatsappNumber') continue;
          expect(code, contains(RegExp('$v\\s*=\\s*whatsappNumber\\(')),
              reason: '$rel: «$v» بعد wa.me/ غيرُ مُسنَدٍ من whatsappNumber');
        }
      }
    });

    test('وزرُّ الأدمنِ يَتكلّمُ عند تعذّرِ الفتحِ وعند غيابِ الرقم', () {
      final admin =
          stripLineComments(read('lib/screens/admin/admin_order_details_screen.dart'));
      final i = admin.indexOf('Future<void> _openWhatsApp(');
      expect(i, greaterThan(0));
      final body = admin.substring(i, admin.indexOf('\n  }\n', i));
      expect(body, contains('number.isEmpty'),
          reason: 'طلبٌ بلا رقمٍ يَفتح wa.me/ فارغاً بلا كلمة');
      expect(body, contains('} else if (mounted) {'),
          reason: 'canLaunchUrl == false ما زال صامتاً');
      expect('ScaffoldMessenger'.allMatches(body).length,
          greaterThanOrEqualTo(3),
          reason: 'المساراتُ الثلاثة (لا رقم / تعذّر الفتح / استثناء) تتكلّم');
    });

    test('والاتجاهُ الذي كان يَعمل ما زال يَعمل', () {
      final tracking =
          stripLineComments(read('lib/screens/order_tracking_screen.dart'));
      expect(tracking, contains('whatsappNumber(phone)'));
    });
  });
}
