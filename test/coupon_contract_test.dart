import 'dart:convert';
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

  // **الجدولُ المشترَكُ مع `endOfLocalDay` في اللوحة.**
  //
  // الملفّانِ يُعلنانِ أنّهما مرآةٌ وكان لكلٍّ فحوصُه الخاصّة، فلا شيءَ يُقابِلُ
  // **الخَرْجَين**. وتعليقُ `lib/utils/coupon_expiry.dart` كان يَقولُ إنّ هذا
  // الفحصَ «يُثبّتُ أنّ المحرّرَين لا يَفترقان» — وهو يُثبّتُ **مواضعَ
  // النداءِ** لا أنّ الدالّتَين تَتّفقان: دعوى أوسعُ من حارسِها، وهو شكلُ ما
  // انحرفت به مرايا هذا المستودعِ من قبل.
  //
  // والمقارنةُ على **مكوّناتِ التاريخِ** لا على الزمنِ المطلق: الجهتانِ تَبنيانِ
  // من مكوّناتٍ محلّيّةٍ فالقيمةُ المطلقةُ تَتبعُ منطقةَ المُشغِّل (وتَختلفُ بين
  // مَهمّةِ Flutter ومَهمّةِ اللوحةِ في CI) بينما المكوّناتُ لا تَتبعُها.
  group('الجدولُ المشترَكُ مع اللوحة', () {
    test('كلُّ صفٍّ: المكوّناتُ المتوقَّعةُ والوقتُ 23:59:59.999', () {
      final src =
          File('admin_panel/src/utils/couponExpiry.test.ts').readAsStringSync();
      final a = src.indexOf('// ⟦CASES⟧');
      final b = src.indexOf('// ⟦/CASES⟧');
      expect(a, greaterThan(0),
          reason: 'علامةُ كتلةِ الحالاتِ مفقودةٌ من فحصِ اللوحة');
      expect(b, greaterThan(a));
      final block = src.substring(a, b);
      final end = block.lastIndexOf(']');
      var depth = 0;
      var start = -1;
      for (var i = end; i >= 0; i--) {
        if (block[i] == ']') depth++;
        if (block[i] == '[') {
          depth--;
          if (depth == 0) {
            start = i;
            break;
          }
        }
      }
      expect(start, greaterThan(-1), reason: 'تعذّرَ اقتطاعُ كتلةِ الحالات');
      var json = block.substring(start, end + 1);
      json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!);
      final rows = (jsonDecode(json) as List<dynamic>)
          .map((r) => (r as List<dynamic>).cast<num>())
          .toList();
      expect(rows.length, greaterThanOrEqualTo(6),
          reason: 'الجدولُ انهارَ — اقتطاعٌ فاشلٌ لا جدولٌ قصير');
      // أصنافٌ لا عدد: كبيسةٌ، وتدحرُجُ شهرٍ، وتدحرُجُ يوم.
      expect(rows.any((r) => r[1] == 2 && r[2] == 29), isTrue,
          reason: 'لا حالةَ يومٍ كبيس');
      expect(rows.any((r) => r[1] > 12), isTrue,
          reason: 'لا حالةَ تدحرُجِ شهر');
      expect(rows.any((r) => r[1] == 2 && r[2] > 28 && r[3] == r[0]), isTrue,
          reason: 'لا حالةَ تدحرُجِ يوم');
      for (final r in rows) {
        final got = endOfDayLocal(
            DateTime(r[0].toInt(), r[1].toInt(), r[2].toInt()));
        final label = '${r[0]}-${r[1]}-${r[2]}';
        expect(got.year, r[3], reason: label);
        expect(got.month, r[4], reason: label);
        expect(got.day, r[5], reason: label);
        expect(got.hour, 23, reason: label);
        expect(got.minute, 59, reason: label);
        expect(got.second, 59, reason: label);
        expect(got.millisecond, 999, reason: label);
      }
    });
  });

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

    test('ولا حقلَ قرارٍ مكتوبٍ ثابتاً — المفتاحُ حاضرٌ والقدرةُ غائبة', () {
      // **الفحصُ أعلاه قارنَ الأسماءَ فمرَّ أخضرَ على هذا.** `restricted_zones`
      // مكتوبٌ في المحرّرَين كليهما، فمجموعتا المفاتيحِ متساويتان — لكنّ
      // اللوحةَ كانت تَكتبُه `[]` **ثابتاً**: المفتاحُ حاضرٌ والقدرةُ غائبة.
      // فلا سبيلَ من اللوحةِ لحصرِ كوبونٍ بمنطقة، ولا لمعرفةِ أنّ كوبوناً
      // محصور — والخادمُ (`functions/coupons.js`) يُنفّذُ الحصرَ فعلاً.
      //
      // وهذا هو النمطُ نفسُه بدرجةٍ أعمق: «حقلُ قرارٍ يَعرفُه مُحرِّرٌ واحد»،
      // إلّا أنّ مقارنةَ المجموعاتِ — الدواءُ المعتادُ — عمياءُ عنه.
      //
      // **والقاعدةُ عامّةٌ، فانتقلَ تنفيذُها إلى حارسٍ مُشتَقِّ النطاق:**
      // `test/editor_payload_capability_test.dart` يَمسحُ كلَّ منطقةِ وسائطَ
      // لكلِّ نداءِ كتابةٍ في اللوحةِ وكلَّ ملفٍّ تحتَ `lib/`. كانت هنا على
      // محرّرَين وحدَهما — «حارسٌ ضيّقٌ وقاعدةٌ عامّة»، في قاعدةٍ كتبتُها
      // أنا. ويَبقى هنا الشاهدُ المحدَّد: الحصرُ من الحالةِ في الجهتَين.
      expect(dartEditor, contains("'restricted_zones': restrictedZones"));
      expect(webEditor, contains('restricted_zones: newZones'));
    });

    test('ومُنتقي المناطقِ في اللوحةِ يَقرأُ المصدرَ نفسَه ويُصفَّرُ بعد الحفظ',
        () {
      // الأسماءُ لا المعرّفات: `functions/coupons.js` يُقارنُ
      // `restricted_zones` بـ`zoneName` — فمعرّفُ مستندٍ هنا يَعني كوبوناً
      // لا يَعملُ في أيِّ منطقةٍ أبداً.
      expect(webEditor, contains("getDocs(collection(db, 'service_zones'))"),
          reason: 'نفسُ مصدرِ محرّرِ Flutter (_fetchZones)');
      expect(dartEditor, contains("collection('service_zones')"));
      expect(webEditor.contains('.name ?? ') || webEditor.contains(".name']"),
          isTrue, reason: 'الاسمُ هو ما يُقارنه الخادم');
      // فشلُ الجلبِ يُقال: قائمةٌ فارغةٌ صامتةٌ تَقرأُ «لا مناطقَ معرّفة».
      expect(webEditor, contains('setZonesFailed(true)'));
      expect(webEditor, contains('تعذّر تحميل المناطق'));
      // والتصفيرُ بعد الحفظ: بلاهُ يَلتصقُ الحصرُ بالكوبونِ التالي — نفسُ
      // عطلِ مفتاحِ «تشغيليّ» في شاشةِ الإشعارات.
      expect(webEditor, contains('setNewZones([])'));
      // ويُرى في الجدول: كوبونٌ محصورٌ كان يَقرأُ كأنّه عامّ.
      expect(webEditor, contains('coupon.restricted_zones.length > 0'));
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

    test('العميلُ يَسألُ القاعدةَ الواحدةَ ولا يَحملُ نسخةً منها', () {
      // **كان هذا الفحصُ يُثبّتُ نسخةَ العميلِ المكتوبةَ بيد** («ولا يُحذَف
      // أحدُها بحجّةِ أنّ الخادمَ يَكفي») — وهو حقٌّ في وقتِه: حذفُ الفحصِ
      // العميليِّ بلا بديلٍ يَعني تطبيقَ كوبونٍ سيَرفضه الخادمُ بصمت.
      //
      // والقرارُ المحروسُ قائم — «لا يُطبَّقُ كوبونٌ مرفوض» — لكنّ النسخةَ
      // زالت: `validateCoupon` تُنادي `validateCouponCode` التي تُنادي
      // `couponProblem` نفسَها. فالتثبيتُ انتقلَ من **النسخةِ** إلى
      // **النداءِ**، وهو أشدّ: النسختانِ كانتا **مختلفتَين** فعلاً
      // (مُرشِّحُ `status` العميليُّ يَحجبُ مستنداً بلا حالة، والخادمُ
      // يَقبلُه)، وهذا الفحصُ كان يَمرُّ أخضرَ على ذلك الافتراق.
      final i = client.indexOf('Future<CouponValidation> validateCoupon');
      expect(i, greaterThan(0), reason: 'توقيعُ الدالّةِ تغيّر — راجِعْ');
      final body = client.substring(i, client.indexOf('\n  }\n', i));
      expect(body, contains("httpsCallable('validateCouponCode')"),
          reason: 'العميلُ لم يَعد يَسألُ الخادم');
      expect(body, contains('CouponValidation.rejected('),
          reason: 'سببُ الرفضِ يَجبُ أن يَصلَ الشاشة');
      // ولا نسخةَ ثانيةً باقيةً: لا استعلامَ للمجموعةِ ولا فحصَ حقلٍ.
      final clientCode = stripLineComments(client);
      for (final gone in [
        "'status', isEqualTo: 'active'",
        "data['expiry']",
        'maxUses > 0 && uses >= maxUses',
        "data['target_user_id']",
        "data['restricted_zones']",
      ]) {
        expect(clientCode.contains(gone), isFalse,
            reason: 'عادت نسخةُ العميلِ: $gone');
      }
      // والشاشةُ تَمنعُ التطبيقَ على الرفض — وهو القرارُ الأصليُّ المحروس.
      final pay = stripLineComments(read('lib/screens/payment_summary_screen.dart'));
      expect(pay, contains('if (result.ok) {'));
      expect(pay, contains('_appliedCoupon = null;'));
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
