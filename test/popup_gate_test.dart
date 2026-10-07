import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/broadcast_target.dart';
import 'package:zyiarah/utils/popup_gate.dart';

/// **الإعلانُ المنبثقُ كان يَتخطّى إيقافَ التسويقِ كلَّه.**
///
/// القاعدةُ المعلنةُ في `functions/notify_prefs.js`: البثُّ الإداريُّ
/// (`notifications_log`) **تسويقيٌّ افتراضياً** ما لم يُوسَم
/// `operational: true`، و`_deliverBroadcast` يُسقط عن التسويقيِّ كلَّ من أوقف
/// «العروض والتسويق» — بوشاً وصندوقاً داخل التطبيق.
///
/// والمنبثقُ لا يَمرُّ بذلك المسارِ إطلاقاً، من طرفَيه:
///
///   * `onNotificationCreated` يَرجعُ مبكراً عند `type === "popup"` —
///     **بحقّ**: المنبثقُ نافذةٌ داخلَ التطبيقِ فقط، وبلا ذلك الحارسِ كان
///     إعلانٌ واحدٌ يُطلق ثلاثَ قنواتٍ دفعةً واحدة. لكنّ الأثرَ الجانبيَّ أنّ
///     `excludeOptedOut` لا يَعملُ معه.
///   * والعميلُ يَقرأ `notifications_log where type == 'popup'` **مباشرةً**
///     (`firestore.rules` تُجيزه لكلِّ مسجَّل) — فلا إسقاطَ خادميّاً أصلاً.
///
/// فمن أوقفت التسويقَ **صراحةً** كانت تَرى الإعلانَ على كلِّ فتحٍ للتطبيقِ
/// طولَ أربعٍ وعشرين ساعة. القرارُ الآن نقيٌّ في `lib/utils/popup_gate.dart`
/// ويُسأل عميليّاً، لأنّ القراءةَ عميليّة.
///
/// **ولم يُغيَّر** أنّه لا علمَ «شُوهد» في أيِّ مكان: الإعلانُ يُعاد على كلِّ
/// فتحٍ داخلَ النافذة. سلوكٌ قائمٌ وقرارُه للمالك، لا عطلٌ أُصلح بالسكوت.
///
/// **والنصفُ الثاني من الحفرةِ نفسِها (2026-10-07): الجمهور.** الشرحُ أعلاه
/// يَقولُ إنّ `_deliverBroadcast` لا يَعملُ للمنبثق — وذاك المسارُ هو
/// الموضعُ **الوحيدُ** الذي يُرشِّحُ بـ`target`. فالإصلاحُ الأوّلُ أخذَ منه
/// `excludeOptedOut` وتركَ المُرشِّح: إعلانٌ منبثقٌ موسومٌ «السائقين فقط»
/// كان يُعرَضُ لكلِّ عميلةٍ تَفتحُ التطبيق، ولا يَراه سائقٌ واحد. والوسيطُ
/// `audience` **مطلوبٌ** لا مُفترَضٌ لذلك بعينِه.
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

  final now = DateTime.utc(2026, 10, 5, 12);
  Map<String, dynamic> popup({DateTime? sentAt, bool? operational}) => {
        'title': 'عرض',
        'body': 'نصّ',
        if (sentAt != null) 'sent_at': Timestamp.fromDate(sentAt),
        if (operational != null) 'operational': operational,
      };

  group('القاعدة', () {
    test('تسويقيٌّ حديثٌ: يُعرض للمُفعِّلةِ ولا يُعرض للمُوقِفة — العطلُ بعينه',
        () {
      final fresh = popup(sentAt: now.subtract(const Duration(hours: 2)));
      expect(shouldShowPopup(fresh, now: now, marketingEnabled: true, audience: kClientAudience), isTrue);
      expect(shouldShowPopup(fresh, now: now, marketingEnabled: false, audience: kClientAudience), isFalse,
          reason: 'من أوقفت التسويقَ صراحةً كانت تَراه على كلِّ فتح');
    });

    test('التشغيليُّ يَصلُ الجميعَ — كما في البثِّ تماماً', () {
      final op = popup(
          sentAt: now.subtract(const Duration(hours: 2)), operational: true);
      expect(shouldShowPopup(op, now: now, marketingEnabled: false, audience: kClientAudience), isTrue);
      expect(shouldShowPopup(op, now: now, marketingEnabled: true, audience: kClientAudience), isTrue);
      // و«غيرُ تشغيليّ» تُقرأ صارمةً: أيُّ قيمةٍ غيرِ `true` تسويقيّة.
      for (final v in [false, 'true', 1, null]) {
        final x = popup(sentAt: now.subtract(const Duration(hours: 2)));
        if (v != null) x['operational'] = v;
        expect(shouldShowPopup(x, now: now, marketingEnabled: false, audience: kClientAudience), isFalse,
            reason: 'operational=$v');
      }
    });

    test('النافذةُ أربعٌ وعشرون ساعة — والحدُّ مُغلَق', () {
      expect(kPopupMaxAge, const Duration(hours: 24));
      final almost = popup(
          sentAt: now.subtract(kPopupMaxAge - const Duration(seconds: 1)));
      expect(shouldShowPopup(almost, now: now, marketingEnabled: true, audience: kClientAudience), isTrue);
      final exact = popup(sentAt: now.subtract(kPopupMaxAge));
      expect(shouldShowPopup(exact, now: now, marketingEnabled: true, audience: kClientAudience), isFalse);
      final old = popup(sentAt: now.subtract(const Duration(days: 30)));
      expect(shouldShowPopup(old, now: now, marketingEnabled: true, audience: kClientAudience), isFalse);
    });

    test('بلا لحظةِ إرسالٍ لا نَعرض — عمرٌ مجهولٌ قد يكون من العامِ الماضي', () {
      expect(shouldShowPopup(popup(), now: now, marketingEnabled: true, audience: kClientAudience),
          isFalse);
      expect(
          shouldShowPopup({'sent_at': 'ليس طابعاً', 'title': 'x'},
              now: now, marketingEnabled: true, audience: kClientAudience),
          isFalse);
      expect(shouldShowPopup(null, now: now, marketingEnabled: true, audience: kClientAudience), isFalse);
    });

    test('لحظةُ إرسالٍ في المستقبلِ لا تُعرض (ساعةُ جهازٍ متأخّرة)', () {
      final future = popup(sentAt: now.add(const Duration(hours: 3)));
      expect(shouldShowPopup(future, now: now, marketingEnabled: true, audience: kClientAudience), isFalse);
    });
  });

  group('الجمهور — النصفُ الثاني من الحفرة', () {
    Map<String, dynamic> t(String? target) {
      final m = popup(sentAt: now.subtract(const Duration(hours: 2)));
      if (target != null) m['target'] = target;
      return m;
    }

    test('إعلانُ «السائقين فقط» لا يُعرَضُ للعميلة — العطلُ بعينه', () {
      expect(
          shouldShowPopup(t('drivers'),
              now: now, marketingEnabled: true, audience: kClientAudience),
          isFalse,
          reason: 'كان يُعرَضُ لكلِّ عميلةٍ تَفتحُ التطبيق');
      expect(
          shouldShowPopup(t('drivers'),
              now: now, marketingEnabled: true, audience: kDriverAudience),
          isTrue,
          reason: 'ويُعرَضُ لجمهورِه');
    });

    test('و«الإدارة فقط» لا يُعرَضُ لعميلةٍ ولا لسائق', () {
      for (final a in const [kClientAudience, kDriverAudience]) {
        expect(
            shouldShowPopup(t('admins'),
                now: now, marketingEnabled: true, audience: a),
            isFalse,
            reason: a);
      }
    });

    test('و«الجميع» يُعرَضُ للجميعِ — وكذلك غيابُ الحقلِ والقيمةُ المجهولة',
        () {
      for (final v in <String?>['all', null, '', 'شيءٌ آخر']) {
        expect(popupTargetsAudience(t(v), audience: kClientAudience), isTrue,
            reason: 'target=$v');
        expect(popupTargetsAudience(t(v), audience: kDriverAudience), isTrue,
            reason: 'target=$v');
      }
    });

    test('و`all_users` يُحَلُّ عبرَ قاعدةِ الجمهورِ — مستنداتُ الإنتاجِ تَحملُه',
        () {
      // المسارُ المجدولُ كتبَ اسمَ موضوعِ FCM في الحقلِ حتى 2026-10-07؛
      // إصلاحُ الكاتبِ لا يُعيدُ كتابةَ ما كُتب.
      expect(popupTargetsAudience(t('all_users'), audience: kClientAudience),
          isTrue);
      expect(
          shouldShowPopup(t('all_users'),
              now: now, marketingEnabled: true, audience: kClientAudience),
          isTrue);
    });

    test('والتشغيليُّ لا يَرفعُ الجمهورَ — الترتيبُ هو الإصلاح', () {
      // «تشغيليٌّ» يَرفعُ تفضيلَ التسويقِ وحدَه. وإشعارٌ تشغيليٌّ للسائقين
      // («الورشةُ مغلقةٌ اليوم») ليس للعميلة — فلو جاءَ فحصُ الجمهورِ بعدَ
      // قِصَرِ `operational` لَعادَ العطلُ لأسوأِ حالةٍ منه.
      final op = t('drivers')..['operational'] = true;
      expect(
          shouldShowPopup(op,
              now: now, marketingEnabled: false, audience: kClientAudience),
          isFalse);
      final opAll = t('all')..['operational'] = true;
      expect(
          shouldShowPopup(opAll,
              now: now, marketingEnabled: false, audience: kClientAudience),
          isTrue,
          reason: 'والتشغيليُّ لجمهورِها ما زال يَتخطّى تفضيلَ التسويق');
    });

    test('وأسماءُ الجمهورِ هي قيمُ الحقلِ نفسُها — لا خريطةَ ثانية', () {
      expect(kClientAudience, 'clients');
      expect(kDriverAudience, 'drivers');
      expect(kBroadcastTargets.contains(kClientAudience), isTrue);
      expect(kBroadcastTargets.contains(kDriverAudience), isTrue);
    });
  });

  group('قراءةُ التفضيل', () {
    test('الغيابُ = مُفعَّل — نفسُ تسامحِ شاشةِ التفضيلات', () {
      expect(marketingEnabledFrom(null), isTrue);
      expect(marketingEnabledFrom({}), isTrue);
      expect(marketingEnabledFrom({'notification_prefs': {}}), isTrue);
      expect(marketingEnabledFrom({'notification_prefs': 'نصّ'}), isTrue);
    });

    test('و`false` صريحةٌ وحدَها تُوقِف', () {
      expect(
          marketingEnabledFrom({
            'notification_prefs': {'marketing': false}
          }),
          isFalse);
      expect(
          marketingEnabledFrom({
            'notification_prefs': {'marketing': true}
          }),
          isTrue);
    });

    test('والقاعدةُ هي عينُها في شاشةِ التفضيلات — لا نسخةٌ ثانية', () {
      final screen =
          stripLineComments(read('lib/screens/client_notifications_screen.dart'));
      expect(screen, contains("prefs['marketing'] != false"),
          reason: 'القاعدةُ تغيّرت هناك — وهذه نسختُها');
    });
  });

  group('حارسُ المصدر', () {
    final svc = stripLineComments(read('lib/services/popup_service.dart'));

    test('الخدمةُ تَسألُ القرارَ ولا تُعيدُ صياغتَه', () {
      expect(svc, contains('shouldShowPopup(data'),
          reason: 'الخدمةُ لا تَسألُ البوّابة');
      expect(svc, contains('marketingEnabledFrom('));
      expect(svc.contains('.inHours < 24'), isFalse,
          reason: 'شرطُ العمرِ عاد إنلاين — فالبوّابةُ بلا موضوع');
    });

    /// القرارُ هو هو («لا قراءةَ تفضيلٍ إلّا عند الحاجة») وقد انتقلَ موضعُه
    /// بمسحِ عدّةِ مستنداتٍ بدلَ واحد: قِصَرُ `operational` صارَ عند موضعِ
    /// النداءِ لا داخلَ الدالّة (لأنّ النتيجةَ صارت محفوظةً، وحفظُ `true`
    /// لإعلانٍ تشغيليٍّ كان سيُجيزُ تسويقيّاً بعدَه). فالمشدودُ **الترتيبُ**
    /// لا نصُّ موضعٍ بعينِه — وسقوطُ هذا الفحصِ على النقلِ هو ما يُراجَع.
    test('وتَقرأُ التفضيلَ فقط عند الحاجة — ترتيباً', () {
      final int i = svc.indexOf('Future<bool> marketingEnabled()');
      expect(i, greaterThan(0), reason: 'القراءةُ المؤجَّلةُ اختفت');
      final int body = svc.indexOf('.get()', i);
      expect(body, greaterThan(i), reason: 'قراءةُ المستخدمِ اختفت');
      expect(svc.substring(i, body + 60), contains('kNetCallTimeout'),
          reason: 'قراءةٌ بلا مهلةٍ تُعلّق المسارَ بصمت');

      final int call = svc.indexOf('await marketingEnabled()');
      expect(call, greaterThan(0), reason: 'موضعُ النداءِ اختفى');
      final int prune = svc.indexOf('popupTargetsAudience(data', call - 900);
      final int op = svc.indexOf("data['operational'] == true", call - 400);
      expect(prune, greaterThan(0),
          reason: 'لا تقليمَ بالجمهورِ قبلَ القراءة');
      expect(prune, lessThan(call),
          reason: 'قراءةُ تفضيلٍ لإعلانٍ ليس لهذا الجمهورِ أصلاً');
      expect(op, greaterThan(prune),
          reason: 'قِصَرُ التشغيليِّ يجب أن يَلي التقليمَ');
      expect(op, lessThan(call),
          reason: 'التشغيليُّ يجب أن يَخرجَ قبل أيِّ قراءة');
    });

    /// **قدرةً لا اسماً:** أوّلُ صياغةٍ كانت `contains('bool? marketingCache')`
    /// فمرَّ قضمٌ أعادَ تسميةَ التعريفِ إلى `marketingCacheUnused` **أخضرَ** —
    /// الاحتواءُ يُرضيه أيُّ اسمٍ يَبدأُ بالاسمِ نفسِه، وهو فخُّ
    /// `packageFormErrorX` بعينِه. فالمشدودُ: متغيّرٌ **خارجَ** الدالّةِ،
    /// يُقرأُ ويُرجَعُ **قبلَ** الـI/O، ويُكتَبُ **بعدَها**. والاسمُ حرٌّ.
    test('ونتيجةُ التفضيلِ محفوظةٌ — قراءةٌ واحدةٌ لا خمس', () {
      final int i = svc.indexOf('Future<bool> marketingEnabled()');
      expect(i, greaterThan(0));
      final m = RegExp(r'bool\?\s+(\w+);').firstMatch(svc.substring(0, i));
      expect(m, isNotNull,
          reason: 'لا ذاكرةَ للتفضيلِ خارجَ الدالّة — فكلُّ مستندٍ قراءةٌ');
      final String cache = m!.group(1)!;
      final int get = svc.indexOf('.get(', i);
      expect(get, greaterThan(i), reason: 'قراءةُ المستخدمِ اختفت');
      // **قراءةٌ لا ذِكرٌ:** قضمةٌ نزعت الرجوعَ المبكّرَ وأبقت الكتابةَ
      // (`return marketingCache = false;`) فمرَّ `indexOf` أخضرَ — فالعدُّ
      // على الورودِ **غيرِ** المتبوعِ بإسنادٍ وحدَه.
      final int reads = RegExp('\\b$cache\\b(?!\\s*=[^=])')
          .allMatches(svc.substring(i, get))
          .length;
      expect(reads, greaterThanOrEqualTo(1),
          reason: 'الذاكرةُ تُكتَبُ ولا تُقرأُ قبلَ القراءةِ الشبكيّة — '
              'فكلُّ مستندٍ قراءةٌ جديدةٌ والحفظُ بلا أثر');
      expect(svc.substring(get).contains('$cache ='), isTrue,
          reason: 'نتيجةُ القراءةِ لا تُحفَظ');
    });

    test('وغيابُ الهويّةِ لا يَعرضُ تسويقاً', () {
      expect(svc, contains('if (uid == null) return marketingCache = false;'),
          reason: 'بلا هويّةٍ لا نَعرفُ التفضيلَ — والخطأُ يجب أن يَميلَ '
              'إلى احترامِه لا إلى العرض');
    });

    test('والخدمةُ تُمرّرُ جمهورَ هذا السطحِ ولا تَفترضُه', () {
      expect(svc, contains('audience: kClientAudience'),
          reason: 'الوسيطُ مطلوبٌ لذلك بعينِه');
      expect(svc.contains('audience: kDriverAudience'), isFalse,
          reason: 'هذه الدالّةُ مُنادةٌ من لوحةِ العميلةِ وحدَها — '
              'لو وُصِلت لوحةُ السائقِ فهذا الفحصُ هو ما يُراجَع');
      // والمُنادي ما زال واحداً: لو صارَ اثنَين فالجمهورُ يَلزمُه وسيطٌ من
      // المُنادي لا ثابتٌ في الخدمة.
      final callers = Directory('$repo/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('services/popup_service.dart'))
          .where((f) =>
              stripLineComments(f.readAsStringSync()).contains('checkAndShowPopup('))
          .map((f) => f.path.split('/lib/').last)
          .toList();
      expect(callers, ['screens/client_dashboard.dart'],
          reason: 'مُنادٍ ثانٍ — فالجمهورُ لم يَعُد ثابتاً: $callers');
    });

    test('ونافذةُ المسحِ خمسةٌ بفهرسِها القائمِ — لا فهرسٌ جديد', () {
      expect(kPopupScanLimit, 5);
      expect(svc, contains('.limit(kPopupScanLimit)'),
          reason: 'حدٌّ مكتوبٌ في موضعِه يَنحرِفُ عن الثابت');
      expect(svc.contains('.limit(1)'), isFalse,
          reason: 'إعلانٌ لجمهورٍ آخرَ يَحجبُ إعلاناً حيّاً لهذا الجمهور');
      // المُرشِّحُ مساواةٌ مع `orderBy` على حقلٍ آخرَ ⇒ فهرسٌ مركَّبٌ لازم،
      // وهو قائمٌ — فرفعُ الحدِّ كلفتُه قراءاتٌ لا فهرس.
      final ix = read('firestore.indexes.json');
      expect(ix, contains('"notifications_log"'));
      expect(
          RegExp(r'notifications_log[\s\S]{0,260}?"type"[\s\S]{0,200}?"sent_at"')
              .hasMatch(ix),
          isTrue,
          reason: 'فهرسُ (type, sent_at) زال — فالاستعلامُ يَفشلُ أصلاً');
    });

    test('والخادمُ ما زال يَستثني المنبثقَ من قنواتِ البثّ', () {
      // لو زالَ ذلك الاستثناءُ لعاد الإعلانُ يُطلق ثلاثَ قنوات، **و**لصار
      // الإسقاطُ الخادميُّ يَعملُ فيُغني عن هذه البوّابة — فالحالتان تستحقّان
      // مراجعةً لا مروراً صامتاً.
      final idx = stripLineComments(read('functions/index.js'));
      expect(idx, contains('if (newValue.type === "popup") return;'));
    });
  });
}
