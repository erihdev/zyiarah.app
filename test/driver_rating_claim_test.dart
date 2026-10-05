import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **«التقييم ٥٫٠ ★» لسائقٍ لم يُقيّمه أحد — ومرتَّبٌ كأنّه الأفضل.**
///
/// مسارا توفيرِ السائقِ (تطبيقُ الأدمن ولوحةُ الويب) يَبذُران `rating: 5.0`
/// على مستندِ السائقِ **بلا عدّاد**، و`aggregateDriverRating` يَستثني هذا
/// البذرَ من المتوسّطِ صراحةً:
///
///   const avg = count > 0 ? Number(d.rating_avg || d.rating || 0) : 0;
///
/// أي أنّ الخادمَ يَعرفُ أنّ ٥٫٠ ليست تقييماً. ومع ذلك كانت واجهتان تَعرضانها
/// كأنّها مُكتسَبة:
///
///   `admin_staff_performance_screen` .. `rating_avg ?? 5.0` ثمّ **فرزٌ**
///       بـ(التقييم × المُنجَز). فسائقٌ أتمّ ١٧ طلباً بلا تقييمٍ (١٧×٥٫٠ = ٨٥)
///       يَسبقُ من أتمّ ٢٠ بمتوسّطٍ حقيقيٍّ ٤٫٢ (٨٤) — وبطاقةُ «الأفضل» قد
///       تُسمّي من لم يُقيّمه أحد.
///   `admin_panel/src/pages/Drivers.tsx` .. `{driver.rating} ★` خاماً.
///
/// وهو عينُ عطلِ «تقييمك ٤٫٩ ★» في ملفِّ العميلة: رقمٌ لم يَحسبه أحدٌ يُنسَب
/// إلى شخص. الفرقُ أنّ هذا يَصيرُ حقيقيّاً بعد أوّلِ تقييم — فالفاصلُ هو
/// `rating_count` لا وجودُ `rating`.
///
/// **وموضعٌ ثالثٌ بدا متشابهاً وليس عطلاً، وقولُ ذلك جزءٌ من الصدق:**
/// `admin_insights_screen._buildReputationSentinel` يَقرأ `rating ?? 5.0` على
/// **الطلبات** لا السائقين، ويَشترط `rating_comment != null` — فالافتراضُ لا
/// يُدخل طلباً غيرَ مُقيَّمٍ في قائمةِ «التقييمات المنخفضة». تُرك كما هو.
///
/// **وسطحٌ رابعٌ كان عطلاً فعليّاً، وهذا الحارسُ هو ما أخفاه (2026-10-05):**
/// `admin_drivers_screen` — القائمةُ الرئيسةُ للسائقين في تطبيقِ الإدارة —
/// كان يَعرضُ `(driver['rating_avg'] ?? 5.0).toStringAsFixed(1)` بنجمةٍ
/// كهرمانيّةٍ، **وتحتَه مباشرةً «(٠ تقييم)»**: سطرانِ يُكذّبانِ أحدَهما الآخرَ
/// في البطاقةِ عينِها. وشارةُ «متميّز» في الملفِّ نفسِه تَشترطُ العدّادَ
/// بصحّة — فالقاعدةُ كانت معروفةً ومطبَّقةً في موضعٍ ومُغفَلةً في الآخر.
///
/// وهذا الحارسُ كان يَقرأُ **قائمةً مكتوبةً بيدٍ** من ملفَّين، والقاعدةُ
/// عامّة — نمطُ «حارسٌ ضيّقٌ وقاعدةٌ عامّة» الذي تَكرّرَ في هذا المستودعِ
/// مرّاتٍ (نصُّ الاستثناءِ الخامّ، و`no_dead_code_test`، و`zone_locator_test`).
/// فالنطاقُ الآن **مُشتَقّ**: كلُّ ملفٍّ تحت `lib/` يَقرأُ `rating_avg` يَجبُ
/// أن يَمرَّ بالقاعدةِ الواحدةِ (`lib/utils/driver_rating.dart`) أو يُستثنى
/// بسببٍ مكتوبٍ هنا. والقاعدةُ نفسُها تُختبَرُ قيميّاً في
/// `test/driver_rating_rule_test.dart`.
void main() {
  _serverOwnsRatingSideEffects();
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  final perf = read('lib/screens/admin/admin_staff_performance_screen.dart');
  final web = read('admin_panel/src/pages/Drivers.tsx');
  final idx = read('functions/index.js');

  group('الخادمُ نفسُه يَستثني البذر', () {
    test('المتوسّطُ يُؤسَّس من الصفرِ عند أوّلِ تقييم', () {
      expect(stripLineComments(idx),
          contains('count > 0 ? Number(d.rating_avg || d.rating || 0) : 0'),
          reason: 'القاعدةُ تغيّرت — أعِد تقييمَ الواجهتَين معها');
      expect(stripLineComments(idx), contains('rating_count: newCount'));
    });

    test('والبذرُ ما زال يُكتب بلا عدّاد (وإلّا فالحارسُ بلا موضوع)', () {
      expect(web, contains('rating: 5.0'),
          reason: 'لوحةُ الويبِ لم تَعد تَبذُر — راجِع هذا الملفّ كلَّه');
      expect(web.contains('rating_count: 0'), isFalse,
          reason: 'لو بُذر العدّادُ صفراً لصار الفاصلُ غيرَ ذي معنى');
    });
  });

  group('الواجهتان لا تَنسِبان ما لم يَقُله أحد', () {
    test('شاشةُ الأداء: بلا تقييمٍ = null لا ٥٫٠', () {
      final code = stripLineComments(perf);
      expect(code, contains("driverData['rating_count']"),
          reason: 'الفاصلُ هو العدّادُ — بلا قراءتِه لا سبيلَ إلى التمييز');
      // **كان هنا `ratingCount <= 0` نصّاً.** الشرطُ انتقلَ إلى القاعدةِ
      // الواحدةِ حين ظهرَ السطحُ الرابع، فالتثبيتُ صارَ على النداءِ لا على
      // نسخةٍ محليّةٍ منه — تحديثٌ مقصودٌ يُشدّدُ لا يُرخي: لو عادت نسخةٌ
      // محليّةٌ سَقطَ فحصُ النطاقِ المُشتَقِّ أدناه.
      expect(code, contains('driverRatingOf('),
          reason: 'القاعدةُ في موضعٍ واحد — ونسخةٌ محليّةٌ هي ما سمحَ '
              'لـadmin_drivers_screen بالانحراف');
      expect(code.contains("rating_avg'] ?? 5.0"), isFalse,
          reason: 'افتراضُ ٥٫٠ عاد');
      expect(code.contains("?? 5.0"), isFalse,
          reason: 'أيُّ افتراضٍ لتقييمٍ غائبٍ في هذه الشاشةِ هو العطلُ نفسه');
    });

    test('والفرزُ لا يَرفعُ غيرَ المُقيَّمِ فوق المُقيَّم', () {
      final code = stripLineComments(perf);
      expect(code, contains('if (ar == null) return 1;'),
          reason: 'غيرُ المُقيَّمِ يجب أن يَلي المُقيَّمَ لا أن يُضرَب برقمٍ مُختلَق');
      expect(code, contains('if (br == null) return -1;'));
      expect(code.contains("(b['rating'] * b['completed'])"), isFalse,
          reason: 'الفرزُ القديمُ عاد — يَضربُ رقماً قد يكون مُختلَقاً');
    });

    test('والعرضُ «—» لا رقم', () {
      expect(stripLineComments(perf), contains('"—"'),
          reason: 'لا بديلَ نصّيٌّ لغيابِ التقييم');
    });

    test('ولوحةُ الويبِ كذلك', () {
      final code = stripLineComments(web);
      expect(code, contains('(driver.rating_count ?? 0) > 0'),
          reason: 'اللوحةُ تَعرضُ البذرَ كأنّه تقييم');
      expect(code, contains('rating_count?: number'),
          reason: 'الحقلُ غيرُ مُعلَنٍ في النوع');
      expect(code.contains('{driver.rating} <Star'), isFalse,
          reason: 'العرضُ الخامُّ عاد');
    });
  });

  group('والموضعُ الثالثُ تُرك عمداً', () {
    test('حارسُ السمعةِ يَقرأ الطلباتِ ويَشترطُ تعليقاً — فالافتراضُ غيرُ ضار', () {
      final insights = read('lib/screens/admin/admin_insights_screen.dart');
      expect(insights, contains("data['rating_comment'] != null"),
          reason: 'لو سقطَ شرطُ التعليقِ لصار `?? 5.0` هناك عطلاً فعليّاً');
    });
  });

  group('النطاقُ مُشتَقٌّ لا مكتوبٌ بيد', () {
    // **السطحُ الرابعُ نَجا لأنّ هذا الحارسَ كان قائمةَ ملفَّين.** فالنطاقُ
    // الآن يُشتَقُّ من الشفرةِ: كلُّ قارئٍ لـ`rating_avg` تحت `lib/` إمّا
    // يَمرُّ بالقاعدةِ أو يُستثنى بسببٍ مكتوبٍ أدناه.
    //
    // المستثنَون:
    //   • `lib/utils/driver_rating.dart` — القاعدةُ نفسُها.
    //   • `lib/models/user_model.dart` — ذِكرٌ في تعليقٍ لا قراءةٌ لحقل.
    //   • `lib/screens/order_tracking_screen.dart` — يَقرأُ
    //     `driver_rating_avg` على **الطلب** لا على مستندِ السائق، ولا
    //     يَرسمُ نجمةً بلا قيمةٍ (مُعلَّلٌ في الملفِّ نفسِه).
    const Set<String> exempt = {
      'lib/utils/driver_rating.dart',
      'lib/models/user_model.dart',
      'lib/screens/order_tracking_screen.dart',
    };

    test('كلُّ قارئٍ لـrating_avg يَمرُّ بالقاعدةِ أو يُستثنى بسبب', () {
      final List<String> offenders = [];
      int scanned = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final rel = f.path.replaceFirst('$repo/', '');
        final src = f.readAsStringSync();
        if (!src.contains('rating_avg')) continue;
        scanned++;
        if (exempt.contains(rel)) continue;
        final code = stripLineComments(src);
        if (!code.contains('rating_avg')) continue; // ذِكرٌ في تعليقٍ فقط
        if (!code.contains('driverRatingOf(') &&
            !code.contains('driverRatingLabel(') &&
            !code.contains('driverIsRated(')) {
          offenders.add(rel);
        }
      }
      expect(scanned, greaterThanOrEqualTo(4),
          reason: 'المسحُ لم يَجد القُرّاءَ المعروفين — نمطٌ معطوبٌ لا شفرةٌ '
              'سليمة (حارسٌ عقيمٌ أسوأُ من غائب)');
      expect(offenders, isEmpty,
          reason: 'قارئٌ لتقييمِ سائقٍ لا يَمرُّ بالقاعدةِ — وهو بعينِه ما '
              'أخفاه هذا الحارسُ في `admin_drivers_screen`');
    });

    test('ولا افتراضَ ٥٫٠ باقياً في أيِّ شاشةٍ تَقرأُ تقييمَ سائق', () {
      for (final rel in [
        'lib/screens/admin/admin_drivers_screen.dart',
        'lib/screens/admin/admin_staff_performance_screen.dart',
      ]) {
        final code = stripLineComments(read(rel));
        expect(code.contains("rating_avg'] ?? 5.0"), isFalse,
            reason: '$rel: افتراضُ ٥٫٠ عاد');
      }
      // والمضادّة: الرقمُ ما زال مذكوراً في شرحِ إزالتِه.
      expect(read('lib/utils/driver_rating.dart').contains('5.0'), isTrue,
          reason: 'اختفى شرحُ البذرِ — راجِعْ ما جرّدَه الفحص');
    });

    test('والقائمةُ الرئيسةُ لا تَرسمُ نجمةً لمن لم يُقيّمه أحد', () {
      final code = stripLineComments(
          read('lib/screens/admin/admin_drivers_screen.dart'));
      expect(code, contains('driverIsRated('),
          reason: 'النجمةُ الكهرمانيّةُ فوقَ «(٠ تقييم)» كانت التناقضَ عينَه');
      expect(code, contains('driverRatingLabel('));
    });
  });
}

/// العميلةُ تَكتبُ `rating` على الطلبِ وحدَه — والخادمُ يُجمّعُ ويُنبّه.
///
/// كان `submitOrderRating` يَفعلُ ثلاثةَ أشياءَ لا تَعمل: نداءَين للإدارةِ من
/// العميلةِ إلى `ADMIN_BROADCAST` (يَرفضُهما حارسُ الانتحالِ بنصِّه)، وتجميعةً
/// لمعدَّلِ السائقِ تَرفضُها القواعدُ دائماً **ولو نَفذت أفسدت الرقم** (تَبذرُ
/// `5.0` وتُضاعفُ العدَّ مع المُجمّعِ الخادميّ)، وتعليقاً يَنفي وجودَ المُجمّعِ
/// الخادميِّ أصلاً ويُسمّيه «backlog».
void _serverOwnsRatingSideEffects() {
  final svc = File('lib/services/order_service.dart').readAsStringSync();
  final msg = File('lib/services/zyiarah_messaging_service.dart').readAsStringSync();
  final idx = File('functions/index.js').readAsStringSync();

  String code(String src) => src.split('\n').where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      }).join('\n');

  group('آثارُ التقييمِ خادميّةٌ وحدَها', () {
    test('العميلةُ لا تُجمّعُ معدَّلَ السائق', () {
      final c = code(svc);
      // النطاقُ جسمُ `submitOrderRating` وحدَه: `updateOrderStatus` تَلمسُ
      // مستندَ السائقِ بحقّ (حالتُه وتفرُّغُه) ويُجيزُه له الدورُ، فحظرٌ على
      // الملفِّ كلِّه كان توقّعاً خاطئاً — وقد سَقطَ عليه أوّلُ صياغةٍ لهذا
      // الفحص.
      final i = c.indexOf('submitOrderRating(');
      expect(i, greaterThan(-1));
      final body = c.substring(i);
      expect(body.contains("collection('drivers')"), isFalse,
          reason: 'القواعدُ تَرفضُها، ولو نَفذت لضاعفت العدَّ وبذرت 5.0');
      expect(c.contains('rating_avg'), isFalse);
      expect(c.contains('rating_count'), isFalse);
    });

    test('ولا تُنبّهُ الإدارةَ بنفسِها', () {
      expect(code(svc).contains('ZyiarahMessagingService()'), isFalse,
          reason: 'بثُّ العميلِ إلى ADMIN_BROADCAST يُرفَض خادميّاً');
      // والدالّتانِ المرفوضتانِ أُزيلتا من الخدمةِ (وإلّا بَقيتا بلا مُنادٍ).
      expect(msg.contains('alertReputationRisk'), isFalse);
      expect(msg.contains('notifyAdminOfLowRating'), isFalse);
    });

    test('ما زالت تَكتبُ التقييمَ نفسَه ذرّياً', () {
      expect(svc.contains("'rating': rating"), isTrue);
      expect(svc.contains("'rating_comment': comment"), isTrue);
      expect(svc.contains('runTransaction'), isTrue,
          reason: 'منعُ التقييمِ المزدوجِ قرارٌ قائم');
    });

    test('والخادمُ يُجمّعُ ويُنبّهُ فعلاً — فالحذفُ لا يُفقِدُ شيئاً', () {
      expect(idx.contains('exports.aggregateDriverRating'), isTrue);
      expect(idx.contains('exports.notifyAdminOnLowRating'), isTrue);
      // كلاهما مرّةً واحدةً لكلِّ طلب (before.rating غائب).
      expect(RegExp(r'before\.rating != null').allMatches(idx).length, 2);
    });

    test('التعليقُ الكاذبُ أُزيل من الشفرةِ وبقي في شرحِ إزالتِه', () {
      expect(code(svc).contains('لا يوجد Cloud Function'), isFalse);
      expect(svc.contains('لا يوجد Cloud Function'), isTrue,
          reason: 'لو غابَ من الخامِّ فالتجريدُ حَجبَ شيئاً');
    });
  });
}
