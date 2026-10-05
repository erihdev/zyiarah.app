import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/coupon_expiry.dart';

/// عقدُ الكوبونِ — ثلاثةُ أطرافٍ لمستندٍ واحد في `promo_codes`:
///
///   كاتبان: `lib/screens/admin/admin_coupons_screen.dart` (Flutter) و
///           `admin_panel/src/pages/Marketing.tsx` (الويب).
///   قارئان يَقرّران: `lib/services/order_service.dart` (العميل، للعرضِ
///           والتطبيق) و`functions/coupons.js` (الخادم، للمال).
///
/// ═══ ثلاثةُ أعطالٍ وُجدت في هذا العقد ═══
///
/// **١. `expiry` بنوعَين.** محرّرُ Flutter يَكتب `Timestamp`، واللوحةُ كانت
/// تَكتبُ نصَّ `<input type="date">` خاماً. وفحصُ الخادمِ كان
/// `typeof c.expiry.toMillis === "function"` — فالنصُّ لا يَملكه و**الفحصُ
/// يُتخطّى كلَّه**: كلُّ كوبونٍ أُنشئ من اللوحةِ كان **بلا انتهاءٍ خادميّاً**.
/// والعميلُ يَفحصُ النوعَين فيَحجبُه — فكانت الواجهةُ أصرمَ من الخادم.
///
/// **٢. الخادمُ كان يَفحصُ المقدارَ لا الأهليّة.** `_computeTrustedDiscount`
/// وُضع ليَمنعَ العميلَ من تضخيمِ `discount_amount`، وكان يُغفل ثلاثةً
/// يَفحصُها العميلُ كلَّها: `target_user_id` (كوبونُ إحالةٍ موجَّهٌ لعميلةٍ
/// بعينها، وكودُه حتميٌّ ويُرسَل نصّاً في إشعار)، و`restricted_zones`،
/// و`uses`/`maxUses`. الأهليّةُ الآن في `functions/coupons.js`.
///
/// **٣. منتصفُ الليل.** `showDatePicker` يُعيد منتصفَ الليل، و`expiry` يُقارَن
/// `isBefore(now)` — فبطاقةٌ تقول «ينتهي 2026-12-31» كان كوبونُها ميتاً صبحَ
/// ذلك اليوم، و«ينتهي اليوم» ميتاً منذ لحظةِ إنشائه. آخرُ لحظةٍ من اليومِ
/// تُصلحُه في المحرّرَين (`endOfDayLocal` / `endOfLocalDay`).
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();

  // يَحذفُ أسطرَ التعليقِ الكاملةَ فقط — ثمّ نؤكّد أنّ المصطلحَ في الخامِ كي
  // لا يُفرِغَ التجريدُ الفحصَ من موضوعه.
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  group('endOfDayLocal', () {
    test('آخرُ لحظةٍ من اليومِ لا أوّلُها', () {
      final d = endOfDayLocal(DateTime(2026, 12, 31));
      expect(d.year, 2026);
      expect(d.month, 12);
      expect(d.day, 31);
      expect(d.hour, 23);
      expect(d.minute, 59);
      expect(d.second, 59);
      expect(d.millisecond, 999);
    });

    test('كوبونُ «ينتهي اليوم» يَعملُ طولَ اليوم — وكان ميتاً عند منتصفِ الليل',
        () {
      final today = DateTime(2026, 10, 5);
      final exp = endOfDayLocal(today);
      // أيُّ لحظةٍ من ذلك اليومِ أقدمُ من الانتهاء.
      for (final h in [0, 6, 12, 18, 23]) {
        final now = DateTime(2026, 10, 5, h, 30);
        expect(exp.isBefore(now), isFalse, reason: 'الساعة $h');
      }
      // ومنتصفُ الليلِ الخام (ما كان يُخزَّن) ميتٌ منذ 00:30.
      expect(today.isBefore(DateTime(2026, 10, 5, 0, 30)), isTrue);
      // وأوّلُ الغدِ بعدَ الانتهاء.
      expect(exp.isBefore(DateTime(2026, 10, 6)), isTrue);
    });

    test('كلُّ أيّامِ سنةٍ كاملة: اليومُ محفوظٌ والساعةُ آخرُ اللحظة', () {
      for (var m = 1; m <= 12; m++) {
        final last = DateTime(2026, m + 1, 0).day;
        for (var day = 1; day <= last; day++) {
          final d = endOfDayLocal(DateTime(2026, m, day, 7, 13));
          expect(d.month, m);
          expect(d.day, day);
          expect(d.hour, 23);
          expect(d.millisecond, 999);
        }
      }
    });
  });

  group('المحرّران لا يَفترقان', () {
    final dartEditor = read('lib/screens/admin/admin_coupons_screen.dart');
    final webEditor = read('admin_panel/src/pages/Marketing.tsx');

    test('كلاهما يَكتب Timestamp بآخرِ لحظةٍ من اليوم', () {
      expect(dartEditor, contains("'expiry': Timestamp.fromDate(endOfDayLocal("),
          reason: 'محرّرُ Flutter يَكتب منتصفَ الليلِ مرّةً أخرى');
      expect(webEditor,
          contains('expiry: Timestamp.fromDate(endOfLocalDay(newExpiry))'),
          reason: 'اللوحةُ تَكتبُ نصّاً — فحصُ الانتهاءِ الخادميُّ يُتخطّى كلُّه');
      // والنصُّ الخامُّ لا يُكتب من أيِّ جهة.
      expect(RegExp(r'expiry:\s*newExpiry\s*,').hasMatch(webEditor), isFalse);
      expect(dartEditor.contains("'expiry': expiryDate"), isFalse);
    });

    test('مجموعةُ الحقولِ المكتوبةِ واحدةٌ في المحرّرَين', () {
      // المقارنةُ على المجموعةِ كلِّها (كما في app_update_keys_test): حقلٌ
      // في أحدِهما دون الآخرِ يَسقطُ هنا بدل أن يَفترقا بصمت.
      String block(String src, String start, String end) {
        final i = src.indexOf(start);
        expect(i, greaterThan(0), reason: 'لم يُوجد $start');
        final j = src.indexOf(end, i);
        expect(j, greaterThan(i), reason: 'لم يُوجد $end بعد $start');
        return src.substring(i, j);
      }

      final dartBlock = block(dartEditor, 'final newData = {', '};');
      // `[a-zA-Z_]` لا `[a-z_]`: المفاتيحُ مختلطةُ الحالة (`maxUses`،
      // `updatedAt`) — وأوّلُ صياغةٍ أسقطتهما فقالت إنّ المحرّرَين افترقا.
      final dartKeys = RegExp(r"^\s*'([a-zA-Z_]+)':", multiLine: true)
          .allMatches(stripLineComments(dartBlock))
          .map((m) => m.group(1)!)
          .toSet();
      final webBlock =
          block(webEditor, "addDoc(collection(db, 'promo_codes')", '});');
      final webKeys = RegExp(r'^\s*([a-zA-Z_]+):', multiLine: true)
          .allMatches(stripLineComments(webBlock))
          .map((m) => m.group(1)!)
          .toSet();

      // طابعُ الوقتِ يختلفُ اسماً بين المنصّتَين (قرارٌ قائم، لا انحراف).
      Set<String> norm(Set<String> s) => s
          .map((k) => k == 'updatedAt' || k == 'createdAt' ? '_stamp' : k)
          .toSet();
      expect(norm(dartKeys), equals(norm(webKeys)),
          reason: 'المحرّران افترقا — في Dart فقط: '
              '${norm(dartKeys).difference(norm(webKeys))}، '
              'وفي الويب فقط: ${norm(webKeys).difference(norm(dartKeys))}');
      // وفحصٌ أنّ الاستخراجَ ليس فارغاً (وإلّا فالمقارنةُ بلا موضوع).
      expect(dartKeys.length, greaterThanOrEqualTo(10));
    });

    test('كلاهما يَملكُ مُبدِّلَ «يظهر في العروض» — غيابُ الحقلِ = لا', () {
      // القرارُ موثَّق في promo_coupon.dart: الغيابُ = لا، كي لا يُكشف كودُ
      // قناةٍ خاصة. فمحرّرٌ بلا مُبدِّلٍ يُنتج كوبوناً لا يظهرُ أبداً بلا ما
      // يقولُ ذلك — وهو ما كانت اللوحةُ تفعله.
      expect(dartEditor, contains('show_in_offers'));
      expect(webEditor, contains('show_in_offers: newShowInOffers'));
      expect(webEditor, contains('aria-label="الظهور في قسم العروض"'));
    });
  });

  group('القارئان يَسألان الأسئلةَ الخمسةَ نفسَها', () {
    final client = read('lib/services/order_service.dart');
    final server = read('functions/coupons.js');
    final serverCode = stripLineComments(server);

    test('العميلُ يَفحصُ الخمسةَ (ولا يُحذَف أحدُها بحجّةِ أنّ الخادمَ يَكفي)',
        () {
      final i = client.indexOf('Future<Map<String, dynamic>?> validateCoupon');
      expect(i, greaterThan(0));
      final body = client.substring(i, client.indexOf('\n  }\n', i));
      for (final rule in [
        "'status', isEqualTo: 'active'",
        "data['expiry']",
        'maxUses > 0 && uses >= maxUses',
        "data['target_user_id']",
        "data['restricted_zones']",
      ]) {
        expect(body, contains(rule), reason: 'العميلُ لم يَعد يَفحص: $rule');
      }
    });

    test('الخادمُ يَفحصُ الخمسةَ نفسَها — وثلاثةٌ منها كانت مُغفَلة', () {
      for (final rule in [
        'coupon.status',
        'couponExpiryMs',
        'coupon.maxUses',
        'coupon.target_user_id',
        'coupon.restricted_zones',
      ]) {
        expect(serverCode, contains(rule), reason: 'الخادمُ لا يَفحص: $rule');
      }
      // ومجموعةُ الأسبابِ المُعادةِ هي عينُها المعروفة — سببٌ سابعٌ يَسقطُ هنا.
      final reasons = RegExp(r'return "([a-z_]+)";')
          .allMatches(serverCode)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
          reasons,
          equals({
            'not_found',
            'inactive',
            'expired',
            'exhausted',
            'other_user',
            'other_zone',
          }),
          reason: 'أسبابُ الرفضِ تغيّرت — راجِع ESCALATED_PROBLEMS معها');
    });

    test('الخادمُ يَقرأُ نوعَي expiry — وثائقُ النصِّ قائمةٌ في الإنتاج', () {
      expect(serverCode, contains('toMillis'));
      expect(serverCode, contains("typeof raw === \"string\""));
      expect(serverCode, contains('Date.parse'));
    });

    test('index.js لا يُعيدُ صياغةَ الأهليّةِ إنلاين', () {
      final idx = stripLineComments(read('functions/index.js'));
      expect(idx, contains('require("./coupons")'));
      expect(idx, contains('coupons.couponProblem('));
      expect(idx.contains('c.expiry.toMillis'), isFalse,
          reason: 'فحصُ الانتهاءِ القديمُ (الأعمى للنصّ) ما زال في index.js');
      expect(idx, contains('coupon_rejected_reason'),
          reason: 'رفضُ خصمٍ 10% يُنتج ratio=0.9 فلا يَبلغُ عتبةَ الوسمِ — '
              'بلا وسمٍ صريحٍ يَذهبُ الإنفاذُ إلى اللاشيء');
    });
  });
}
