// حارسُ **قائمةِ منعِ الإنشاء**: كلُّ علَمِ ثقةٍ خادميٍّ على الطلبِ محجوبٌ
// عن العميلِ عند الإنشاء — **مُشتَقّاً من الخادمِ لا مكتوباً بيد**.
//
// ═══ لماذا مُشتَقّاً ═══
//
// القائمةُ نُسيت **ثلاثَ مرّاتٍ** في هذا المستودع: بدأت ثمانيةَ أسماء، ثمّ
// أُضيفَ إليها ستّةَ عشَرَ («علَمٌ يَكتبُه العميلُ يُسكِتُ التنبيهَ الوحيدَ
// لمسارِ المحفظة»)، ثمّ خمسةٌ مع بطاقةِ مراجعةِ السعر، ثمّ ثلاثةٌ مع تسويةِ
// الزياراتِ ومكافأةِ الإحالة. وكلُّ مرّةٍ كان الاكتشافُ بالمصادفة. فالقاعدةُ
// هنا تَدورُ على **ما يَكتبُه الخادمُ فعلاً** وتُقابِلُه بالقائمة، فعلَمٌ
// جديدٌ يَسقطُ الفحصَ يومَ كتابتِه لا يومَ استغلالِه.
//
// ═══ وما وجدَه هذا الاشتقاقُ في أوّلِ تشغيل (2026-10-05) ═══
//
// **(١) `server_created_from_payment` — الأثقلُ.** كاتبُه الشرعيُّ
// `verifyMoyasarPayment` حين يُنشئُ الخادمُ الطلبَ من بيانات الدفع (مسارُ
// Apple Pay)، فالمبلغُ لم يُعلِنْه العميلُ. وهو مقروءٌ في موضعَين يَقرّرانِ
// المال: `_tamaraFlipPaid` يَتخطّى **تحقّقَ Tier A كلَّه** إن كان `true`،
// وTier B يَنزعُ الإنفاذَ. فبوليانيٌّ واحدٌ عند الإنشاءِ يَشتري الإعفاءَ من
// الفحصَين.
//
// **(٢) `zone_geo_mismatch`** — `_flagZoneGeoMismatch` يَقولُ في ترويسةِ
// نفسِه إنّ المنطقةَ تُحَلُّ باسمٍ يُرسلُه العميلُ بلا تحقّقٍ أنّ الموقعَ
// داخلَها، «عميلٌ في منطقة أغلى يمكنه إرسال اسم منطقة أرخص» — وأوّلُ سطرٍ
// فيه `if (od.zone_geo_mismatch === true) return null;`. فالعلَمُ يُسقِطُ
// الكاشفَ المكتوبَ للتلاعبِ الذي يُسمّيه: لا وسمَ ولا تنبيه.
//
// والبقيّةُ **اتّساقٌ لا سدُّ هجوم**، ويُقالُ كذلك: لا قارئَ لها اليوم
// (`payment_amount_mismatch`, `coupon_rejected`, `coupon_overlimit`,
// `auto_refund_failed`, `refund_after_assign_conflict`,
// `tamper_gateway_failed`, `reopened_after_late_payment`, `reconciled`)، أو
// ضررُها على مُلفِّقِها وحدَه (`refund_claimed` وأعلامُ تكرارِ الإشعار).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// أسماءٌ يَكتبُها الخادمُ `X: true` وليست علَمَ ثقةٍ على الطلب — ولكلٍّ سببُه.
/// مجموعةٌ كاملةٌ لا عيّنة: اسمٌ جديدٌ خارجَها وخارجَ القائمةِ يَسقطُ الفحصَ.
const Map<String, String> _notAnOrderFlag = {
  // مفاتيحُ كائنٍ **مُعاد** من دالّة، أو جسمُ ردٍّ HTTP — لا حقولَ Firestore.
  'aggregated': 'مفتاحُ عائدِ rewards.aggregateDriverRating',
  'already': 'مفتاحُ عائدِ refund_engine (سُوّيَ سلفاً)',
  'assigned': 'مفتاحُ عائدِ approveAndAssignOrder',
  'available': 'مفتاحُ عائدِ checkHourlySlotAvailability',
  'blocked': 'مفتاحُ عائدٍ (مستخدمٌ محظور)',
  'deleted': 'مفتاحُ عائدِ حذفِ حساب',
  'done': 'مفتاحُ عائدِ refund_engine',
  'handled': 'مفتاحُ عائدِ refund_engine',
  'missing': 'مفتاحُ عائدٍ (مستندٌ غائب)',
  'paid': 'مفتاحُ عائدِ rewards.payReferralBonus',
  'processed': 'مفتاحُ عائدٍ/حقلُ طابورِ الإشعاراتِ لا الطلب',
  'activated': 'مفتاحُ عائدِ _activateContractNow',
  'received': 'جسمُ ردِّ الويب هوك (res.json)',
  'rescheduled': 'مفتاحُ عائدِ rescheduleAssignedOrder',
  'settled': 'مفتاحُ عائدِ rewards.settleVisitAccounting',
  'skipped': 'مفتاحُ عائدٍ',
  'success': 'مفتاحُ عائدٍ',
  // وسائطُ خيارات.
  'merge': 'خيارُ set({merge: true})',
  'retry': 'خيارُ onDocument*({retry: true})',
  // حقولٌ على مجموعاتٍ أخرى — لها قواعدُها.
  'is_available': 'حقلُ drivers (حالةُ اتصالِ السائقِ نفسِه)',
  // (وزالَ `has_active_subscription`: الخادمُ لم يَعُد يَكتبُه على
  // `users/{uid}` — حقلٌ يُحلَّلُ ولا يَقرؤه سطح، حُذفَ 2026-10-08. وهذه
  // القائمةُ تُقارَنُ بمجموعةِ ما يَكتبُه الخادمُ **كاملةً**، فمُدخَلٌ
  // لكاتبٍ زالَ يُسقطُ الفحصَ بدلَ أن يَتعفّن — وقد أسقطَه.)
  'owner_deleted': 'حقلُ wallets — والمحافظُ allow write: if false',
  'ops_negative_alerted': 'حقلُ wallets — allow write: if false',
  'plan_validation_failed': 'حقلُ contracts',
  'visits_generated': 'حقلُ contracts — ممنوعٌ في قاعدةِ إنشاءِ العقدِ نفسِها',
  // حقولُ طلبٍ خارجَ القائمةِ **بقرار**.
  'is_paid': 'محجوبٌ بشرطٍ صريحٍ في القاعدةِ نفسِها: get(is_paid,false) == false',
  'refunded': 'قيمةُ payment_status لا اسمَ حقل',
  'referral_processed':
      'مكتوبٌ ولا قارئَ له في المستودعِ كلِّه — فتلفيقُه لا يُغيّرُ شيئاً '
          '(والمِقصَلةُ referrals.status داخلَ المعامَلة، والمجموعةُ '
          'allow write: if false)',
  // **حقولُ مستندِ العقدِ لا الطلب** — محجوبةٌ في قاعدةِ إنشاءِ `contracts`،
  // والفحصُ أدناه يُثبِتُ ذلك بدلَ أن يَقبلَ الدعوى (كلمةُ `[contracts]`
  // هي مفتاحُ التحقّق).
  'contract_activation_failed': '[contracts] فشلُ معامَلةِ التفعيل',
  'contract_visits_pending': '[contracts] علَمُ إعادةِ توليدِ الزيارات',
};

/// قائمةُ منعِ الإنشاءِ في قاعدةِ **العقود** — بموازنةِ الأقواس.
Set<String> _contractBlocklist(String rules) {
  final i = rules.indexOf('match /contracts/{');
  if (i < 0) throw StateError('كتلةُ قاعدةِ العقودِ اختفت');
  final seg = rules.substring(i, rules.indexOf('allow read', i));
  final h = seg.indexOf('hasAny([');
  if (h < 0) throw StateError('قائمةُ منعِ العقودِ اختفت');
  final open = seg.indexOf('[', h);
  int depth = 0, end = -1;
  for (int j = open; j < seg.length; j++) {
    if (seg[j] == '[') depth++;
    if (seg[j] == ']') {
      depth--;
      if (depth == 0) {
        end = j;
        break;
      }
    }
  }
  if (end <= open) throw StateError('تعذّرَ اقتطاعُ قائمةِ العقود');
  return RegExp(r"'([a-zA-Z0-9_]+)'")
      .allMatches(seg.substring(open, end))
      .map((m) => m.group(1)!)
      .toSet();
}

String _stripJs(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// قائمةُ منعِ الإنشاءِ المشتركة — من **جسمِ `serverTrustFlags()`**
/// بموازنةِ الأقواس لا بأوّلِ `]` (فخُّ الحدِّ المسجَّلُ هنا مرّاتٍ).
///
/// **وكانت تَقرأُ `hasAny([` بعد `match /orders/`** — فحين انتقلت القائمةُ
/// إلى دالّةٍ مشتركةٍ صارَ ذلك النمطُ يَلتقطُ `hasAny(['start_time'])` في
/// فرعِ السائقِ أسفلَ الكتلةِ: مجموعةٌ من اسمٍ واحد، وحارسٌ أجوف. وهو
/// سقوطُ الحارسِ بالنقلِ لا بالانحراف، وقد وقعَ هنا من قبل (فحصا
/// `serviceMeta` بعد نقلِ الملخّص، و`driver_rating_claim_test` بعد نقلِ
/// قاعدةِ البذر). الأرضيّةُ أدناه (`>= 45`) هي ما كشفَه.
/// (ويَرمي بدلَ `expect`: الاستخراجُ في نطاقِ `main` و`expect` هناك
/// غيرُ مشروعٍ — `OutsideTestException`، وهو فخٌّ مسجَّلٌ في هذا المستودع.)
Set<String> _createBlocklist(String rules) {
  final i = rules.indexOf('function serverTrustFlags()');
  if (i < 0) throw StateError('دالّةُ القائمةِ المشتركةِ اختفت');
  final seg = rules.substring(i);
  final h = seg.indexOf('return');
  if (h < 0) throw StateError('جسمُ الدالّةِ بلا return');
  final open = seg.indexOf('[', h);
  int depth = 0, end = -1;
  for (int j = open; j < seg.length; j++) {
    if (seg[j] == '[') depth++;
    if (seg[j] == ']') {
      depth--;
      if (depth == 0) {
        end = j;
        break;
      }
    }
  }
  if (end <= open) throw StateError('تعذّرَ اقتطاعُ القائمة');
  // **الأرقامُ داخلَ الاسمِ جزءٌ منه**: أوّلُ صياغةٍ كانت `[a-z_]+` فلم تَرَ
  // `client_reminder_24h_sent` وأبلغت عنه مفقوداً وهو في القائمة.
  return RegExp(r"'([a-z0-9_]+)'")
      .allMatches(seg.substring(open, end))
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final rules = File('firestore.rules').readAsStringSync();
  final blocked = _createBlocklist(rules);

  test('القائمةُ اقتُطِعت فعلاً (لا فحصٌ أجوف)', () {
    expect(blocked.length, greaterThanOrEqualTo(45),
        reason: 'القائمةُ ${blocked.length} اسماً — الاقتطاعُ أخطأ أو انهارت');
    for (final anchor in const ['driver_id', 'needs_refund', 'is_paid']) {
      // `is_paid` ليس في القائمةِ بل شرطاً صريحاً — فنُثبّتُ الشرطَ نفسَه.
      if (anchor == 'is_paid') continue;
      expect(blocked, contains(anchor),
          reason: 'الاقتطاعُ لم يُصِب القائمةَ المقصودة');
    }
    expect(rules.contains("get('is_paid', false) == false"), isTrue,
        reason: 'شرطُ is_paid الصريحُ زالَ — وهو ما يَحجبُه بدلَ القائمة');
  });

  // ── القاعدةُ المُشتَقّة: ما يَكتبُه الخادمُ `X: true` إمّا محجوبٌ أو مُعلَّل ──
  test('كلُّ علَمٍ يَكتبُه الخادمُ محجوبٌ عند الإنشاءِ أو مُعلَّلٌ باسمِه', () {
    final written = <String, Set<String>>{};
    for (final f in Directory('functions')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .where((f) => !f.path.endsWith('eslint.config.js'))) {
      final src = _stripJs(f.readAsStringSync());
      for (final m
          in RegExp(r'(?:^|[\s{,(])([a-z][a-z0-9_]{3,})\s*:\s*true\b')
              .allMatches(src)) {
        written
            .putIfAbsent(m.group(1)!, () => <String>{})
            .add(f.uri.pathSegments.last);
      }
    }
    expect(written.length, greaterThanOrEqualTo(40),
        reason: 'المسحُ وجدَ ${written.length} اسماً — الاستخراجُ أخطأ');

    final unexplained = written.keys
        .where((k) => !blocked.contains(k))
        .where((k) => !_notAnOrderFlag.containsKey(k))
        .toList()
      ..sort();
    expect(unexplained, isEmpty,
        reason: 'أعلامٌ يَكتبُها الخادمُ ولا هي محجوبةٌ عند الإنشاءِ ولا '
            'مُعلَّلةٌ في `_notAnOrderFlag`: $unexplained — '
            'فعميلٌ يَضبطُها سلفاً، وكلُّ واحدٍ منها كان في المرّاتِ السابقةِ '
            'يُسكِتُ تنبيهاً أو يَتخطّى فحصاً');

    // ولا تَتعفّنُ قائمةُ الإعفاء: اسمٌ فيها لم يَعُد يُكتَبُ يُراجَع.
    final stale = _notAnOrderFlag.keys
        .where((k) => !written.containsKey(k))
        .toList()
      ..sort();
    expect(stale, isEmpty,
        reason: 'إعفاءاتٌ لأسماءٍ لم يَعُد الخادمُ يَكتبُها: $stale');
  });

  // ── والعلَمانِ الحيّانِ: الحجبُ بلا قارئٍ لا معنى له، فيُثبَّتُ القارئ ──
  test('server_created_from_payment محجوبٌ، وقارئاه ما زالا يُقرّرانِ المال',
      () {
    expect(blocked, contains('server_created_from_payment'),
        reason: 'عميلٌ يَدّعي «الخادمُ أنشأني» فيَتخطّى Tier A على مسارِ '
            'تمارا ويَنزعُ إنفاذَ Tier B');
    final idx = _stripJs(File('functions/index.js').readAsStringSync());
    expect(idx.contains('!data.server_created_from_payment'), isTrue,
        reason: 'شرطُ تخطّي Tier A على مسارِ تمارا زالَ — فالسببُ يُراجَعُ لا '
            'يُسكَت');
    expect(idx.contains('od.server_created_from_payment !== true'), isTrue,
        reason: 'شرطُ Tier B زالَ — راجِعْ سببَ الحجب');
    expect(idx.contains('_verifyOrderPriceTierA'), isTrue,
        reason: 'تحقّقُ Tier A نفسُه زالَ');
  });

  test('zone_geo_mismatch محجوبٌ، والكاشفُ ما زال يَخرجُ عليه ويُنبّه', () {
    expect(blocked, contains('zone_geo_mismatch'));
    expect(blocked, contains('zone_geo_distance_m'),
        reason: 'رقمُ البيّنةِ الذي يَقرؤه مَن يُراجِع');
    final idx = _stripJs(File('functions/index.js').readAsStringSync());
    expect(idx.contains('if (od.zone_geo_mismatch === true) return null;'),
        isTrue,
        reason: 'الخروجُ المبكّرُ زالَ — فالحجبُ بلا سبب، يُراجَعُ لا يُسكَت');
    expect(idx.contains('zone_geo_mismatch: true'), isTrue,
        reason: 'الكاشفُ لم يَعُد يَسِمُ الطلب');
    expect(idx.contains('ZONE_GEO_MISMATCH'), isTrue,
        reason: 'سطرُ السجلِّ زال');
    expect(idx.contains('"موقع طلب خارج منطقته ⚠️"'), isTrue,
        reason: 'التنبيهُ الإداريُّ زالَ — فالكاشفُ صامتٌ من جديد');
  });

  test('ولا كاتبَ شرعيّاً للمحجوبِ الجديدِ في العميلِ أو اللوحة', () {
    // ما يَحجبُه هذا التغييرُ تحديداً — كلُّه صفرُ كتاباتٍ عميليّة، وإلّا
    // كان الحجبُ يَكسِرُ إنشاءً سليماً.
    const added = [
      'server_created_from_payment', 'reconciled',
      'zone_geo_mismatch', 'zone_geo_distance_m',
      'payment_amount_mismatch', 'coupon_rejected', 'coupon_overlimit',
      'auto_refund_failed', 'refund_after_assign_conflict',
      'tamper_gateway_failed', 'reopened_after_late_payment',
      'refund_claimed', 'refund_claimed_at', 'payment_push_sent',
    ];
    final client = <File>[
      ...Directory('lib').listSync(recursive: true).whereType<File>().where(
          (f) => f.path.endsWith('.dart')),
      ...Directory('admin_panel/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.ts') || f.path.endsWith('.tsx')),
    ];
    expect(client.length, greaterThanOrEqualTo(120),
        reason: 'مسحُ العميلِ واللوحةِ انهار');
    for (final name in added) {
      for (final f in client) {
        final src = f.readAsStringSync();
        // كتابةٌ تَعني `'name':` أو `name:` في حِملٍ — لا مجرّدَ ذِكر.
        final writes = RegExp("['\"]?$name['\"]?\\s*:").hasMatch(src);
        expect(writes, isFalse,
            reason: '${f.path} يَكتبُ «$name» — والحجبُ يَكسِرُ إنشاءً سليماً، '
                'فراجِعْ قبلَ النشر');
      }
    }
  });

  // ── والأعلامُ الثلاثةُ للتذكيرِ: مُحرِّرُ الإدارةِ يُصفّرُها على update ──
  test('أعلامُ التذكيرِ محجوبةٌ عند الإنشاءِ ومُصفَّرةٌ إداريّاً عند التعديل',
      () {
    for (final f in const [
      'client_reminder_24h_sent',
      'client_reminder_soon_sent',
      'reminder_sent',
    ]) {
      expect(blocked, contains(f), reason: '$f غيرُ محجوبٍ عند الإنشاء');
    }
    // التصفيرُ انتقلَ إلى القاعدةِ المشترَكةِ (2026-10-08) — وهذا الفحصُ كان
    // يُثبّتُ **شكلَ** الكتابةِ إنلاين (`updatePayload['reminder_sent'] =
    // false`) فسقطَ بالنقلِ لا بالانحراف. فالمشدودُ الآن أنّ السطحَ يُنادي
    // القاعدةَ وأنّ القاعدةَ تُصفّرُ الثلاثةَ — والأسماءُ مثبّتةٌ حرفيّاً
    // أعلاه فلا دَورَ على المفحوص.
    final adm = File('lib/screens/admin/admin_order_details_screen.dart')
        .readAsStringSync();
    expect(adm.contains('rescheduleDerivedFields('), isTrue,
        reason: 'تصفيرُ الإدارةِ عند تغييرِ الموعدِ زالَ — وهو `update` لا '
            '`create`، فالحجبُ لا يَمَسُّه');
    final rule = File('lib/utils/booking_fields.dart').readAsStringSync();
    expect(rule.contains('for (final f in kReminderFlags) f: false'), isTrue,
        reason: 'قاعدةُ التحريكِ لم تَعُدْ تُصفّرُ أعلامَ التذكير');
    for (final f in const [
      'client_reminder_24h_sent',
      'client_reminder_soon_sent',
      'reminder_sent',
    ]) {
      expect(rule.contains("'$f',"), isTrue,
          reason: '$f خارجَ kReminderFlags — فتحريكُ الموعدِ لا يُصفّرُه');
    }
  });


  // ═══ والقاعدةُ على السطحَين: `store_orders` كانت تَمنعُ اسمَين ═══
  //
  // `_verifyStoreOrderPrice` هو تحقّقُ السعرِ **الوحيدُ** لطلبِ المتجر،
  // وسياستُه Tier A: وسمٌ وتنبيهٌ لا رفض — فمُخرَجُه كلُّه أعلامٌ على
  // المستند. وقائمةُ منعِ إنشاءِ `store_orders` كانت اسمَين، فكلُّ تلك
  // الأعلامِ مكشوفةٌ للعميلِ عند الإنشاء. وهو نمطُ «قاعدةٌ عامّةٌ مُنفَّذةٌ
  // في سطحٍ واحد» الذي تَكرّر في هذا المستودعِ مرّاتٍ.

  /// جسمُ دالّةٍ في `index.js` بموازنةِ الأقواسِ المعقوفة.
  String bodyOf(String js, String signature) {
    final i = js.indexOf(signature);
    if (i < 0) return '';
    final open = js.indexOf('{', i);
    if (open < 0) return '';
    int depth = 0;
    for (int j = open; j < js.length; j++) {
      if (js[j] == '{') depth++;
      if (js[j] == '}') {
        depth--;
        if (depth == 0) return js.substring(open, j + 1);
      }
    }
    return '';
  }

  test('القائمةُ تَسكنُ مرّةً، ويُنادِيها الموضعان — لا نسخةَ ثانية', () {
    expect(RegExp(r'function\s+serverTrustFlags\(\)').allMatches(rules).length,
        1,
        reason: 'الدالّةُ المشتركةُ غائبةٌ أو مكرَّرة');
    // كلُّ كتلةِ `match` فيها `allow create` تُنادي القائمةَ: الاشتقاقُ
    // يُجيبُ «أيُّ المجموعاتِ محميّة» بدلَ قائمةٍ مكتوبةٍ بيد.
    final callers = <String>{};
    for (final m in RegExp(r'match /(\w+)/\{').allMatches(rules)) {
      final name = m.group(1)!;
      // الكتلةُ من هذا `match` إلى الذي يَليه.
      final next = rules.indexOf('match /', m.end);
      final block = rules.substring(m.start, next < 0 ? rules.length : next);
      if (block.contains('allow create') &&
          block.contains('hasAny(serverTrustFlags())')) {
        callers.add(name);
      }
    }
    expect(callers, containsAll(<String>['orders', 'store_orders']),
        reason: 'مجموعةُ الطلباتِ التي تُنادي القائمةَ المشتركةَ: $callers');
  });

  test('ولا نسخةَ إنلاين باقيةً من القائمةِ في أيِّ قاعدةِ إنشاء', () {
    // نسخةٌ ثانيةٌ تَنحرِف — وهي عِلّةُ انفراطِ السطحَين أصلاً. فلا كتلةَ
    // `match` تَحملُ قائمةً حرفيّةً فيها علَمٌ من المشتركة (عدا
    // `moyasar_payment_id` الخاصِّ بالمتجر — انظر الفحصَ التالي).
    // **النطاقُ مجموعتا الطلباتِ وحدَهما، عن قصد.** كتلةُ `contracts`
    // تَحملُ `paid_confirmed` في قائمتِها الخاصّةِ وهذا **ليس** نسخةً
    // منحرفةً: هي قائمةُ مجموعةٍ أخرى لها قواعدُها، والخطرُ المَحروسُ هنا
    // هو نسخةٌ ثانيةٌ من قائمةِ **الطلبات**. (أوّلُ صياغةٍ كانت على كلِّ
    // كتلةٍ فأبلغت عن `contracts` — وهو إبلاغٌ خاطئ.)
    for (final m in RegExp(r'match /(orders|store_orders)/\{')
        .allMatches(rules)) {
      final next = rules.indexOf('match /', m.end);
      final block = _stripJs(
          rules.substring(m.start, next < 0 ? rules.length : next));
      if (!block.contains('allow create')) continue;
      for (final h in RegExp(r'hasAny\(\[').allMatches(block)) {
        // بموازنةِ الأقواسِ لا بأوّلِ `]` — فخُّ الحدِّ المسجَّلُ هنا مرّاتٍ.
        final open = block.indexOf('[', h.start);
        int depth = 0, end = -1;
        for (int j = open; j < block.length; j++) {
          if (block[j] == '[') depth++;
          if (block[j] == ']') {
            depth--;
            if (depth == 0) {
              end = j;
              break;
            }
          }
        }
        if (end <= open) continue;
        final lit = RegExp(r"'([a-z0-9_]+)'")
            .allMatches(block.substring(open, end))
            .map((x) => x.group(1)!)
            .toSet();
        final leaked = lit.intersection(blocked);
        expect(leaked, isEmpty,
            reason: 'نسخةٌ إنلاين من القائمةِ في ${m.group(1)}: $leaked');
      }
    }
  });

  test('كلُّ علَمٍ يَكتبُه تحقّقُ سعرِ المتجرِ محجوبٌ عند إنشاءِ طلبِ متجر',
      () {
    final js = File('functions/index.js').readAsStringSync();
    final body = bodyOf(js, 'async function _verifyStoreOrderPrice(');
    expect(body.length, greaterThan(400),
        reason: 'لم يُقتطَع جسمُ _verifyStoreOrderPrice — فحصٌ أجوف');
    // الحقولُ المكتوبةُ في `ref.update({...})` داخلَ الدالّة.
    final written = <String>{};
    for (final u in RegExp(r'\.update\(\s*\{').allMatches(body)) {
      final open = body.indexOf('{', u.end - 1);
      int depth = 0, end = -1;
      for (int j = open; j < body.length; j++) {
        if (body[j] == '{') depth++;
        if (body[j] == '}') {
          depth--;
          if (depth == 0) {
            end = j;
            break;
          }
        }
      }
      if (end < 0) continue;
      written.addAll(RegExp(r'^\s*([a-z0-9_]+)\s*:', multiLine: true)
          .allMatches(body.substring(open, end))
          .map((x) => x.group(1)!));
    }
    expect(written.length, greaterThanOrEqualTo(5),
        reason: 'لم تُستخرَج حقولُ الوسمِ ($written) — فحصٌ أجوف');
    expect(written.difference(blocked), isEmpty,
        reason: 'علَمٌ يَكتبُه الخادمُ على طلبِ المتجرِ وليس في القائمة: '
            '${written.difference(blocked)}');
  });

  test('moyasar_payment_id في القائمةِ المشتركة — واستثناءُ المكنسةِ باقٍ', () {
    // **تصحيحٌ لظنٍّ مكتوب:** أبقيتُه أوّلاً محجوباً في `store_orders` وحدَها
    // بحجّةِ أنّ العميلَ يَكتبُه شرعاً على `orders` عند بدءِ الدفع — وفحصُ
    // «لا كاتبَ عميليّاً» أسقطَ الحجّة: صفرُ كاتبٍ في `lib/` واللوحة،
    // وأربعةُ كُتّابٍ خادميّين. فهو علَمُ ثقةٍ خادميٌّ كأخواتِه.
    expect(blocked, contains('moyasar_payment_id'));
    final libWriters = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => RegExp("'moyasar_payment_id'\\s*:")
            .hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(libWriters, isEmpty,
        reason: 'ظهرَ كاتبٌ عميليٌّ — حجبُه يَكسِرُ ذلك المسار: $libWriters');
    final js = File('functions/index.js').readAsStringSync();
    expect(RegExp(r'moyasar_payment_id:').allMatches(js).length,
        greaterThanOrEqualTo(3),
        reason: 'كُتّابُه الخادميّون اختفوا — يُراجَعُ التعليل');
    // وما يَجعلُ حجبَه لازماً هو هذا الاستثناءُ بعينِه: بقاؤه شرطُ صحّةِ
    // التعليل، فزوالُه يَعني مراجعةً لا إسكاتاً.
    expect(_stripJs(js).contains('if (d.moyasar_payment_id) continue;'), isTrue,
        reason: 'استثناءُ cancelStaleUnpaidOrders زال — يُراجَعُ التعليل');
    expect(js.contains('moyasar_payment_id'), isTrue,
        reason: 'المضادّة: الاسمُ ما زال في الخامّ');
  });

  test('ولِلحالتَين المحجوبتَين قارئٌ ما زال قائماً — فالتعليلُ لا يَبيت', () {
    final js = File('functions/index.js').readAsStringSync();
    // (أ) مكنسةُ الوسمِ تَستعلمُ الحقلَين بعينِهما على المجموعتَين، فمستندٌ
    //     يَحملُهما عند الإنشاءِ يَحقنُ تنبيهاً بلا دفعٍ أصلاً.
    expect(js.contains('for (const coll of ["orders", "store_orders"])'), isTrue,
        reason: 'حلقةُ المجموعتَين زالت — تعليلُ حقنِ التنبيهِ يُراجَع');
    expect(
        js.contains('.where("price_mismatch", "==", true)') &&
            js.contains('.where("ops_alerted_mismatch", "==", false)'),
        isTrue,
        reason: 'استعلامُ المكنسةِ تغيّر — القارئُ هو ما يَجعلُ الحجبَ لازماً');
    // (ب) وبطاقةُ الشاشةِ تَرسمُ الحالةَ الخضراءَ من `price_reviewed_*`
    //     وحدَها، فتلفيقُهما شهادةٌ لم يُوقّعها أحد.
    final screen =
        File('lib/screens/admin/admin_store_orders_screen.dart')
            .readAsStringSync();
    expect(screen.contains('priceReviewOf('), isTrue);
    expect(screen.contains("order['price_reviewed_by']"), isTrue,
        reason: 'سطرُ «اعتُمد بواسطة» زال — تعليلُ حجبِ price_reviewed_by يُراجَع');
    final util = File('lib/utils/price_review.dart').readAsStringSync();
    expect(util.contains("order['price_reviewed_at'] != null"), isTrue,
        reason: 'القاعدةُ لم تَعُد تَقرأُ price_reviewed_at — يُراجَع التعليل');
  });


  // ═══ و«حقلُ عقدٍ لا طلب» دعوى تُتحقَّق، لا تُقبَل ═══
  //
  // مُدخَلاتُ `_notAnOrderFlag` المعلَّمةُ بـ`[contracts]` تَقولُ إنّ العلَمَ
  // محجوبٌ في قاعدةِ إنشاءِ العقودِ بدلَ قائمةِ الطلبات. فتلك الدعوى
  // تُقابَلُ بالقائمةِ الأخرى: إعفاءٌ بسببٍ كاذبٍ أسوأُ من إعفاءٍ بلا سبب.
  test('كلُّ إعفاءٍ بحجّةِ «حقلُ عقد» محجوبٌ فعلاً في قاعدةِ العقود', () {
    final contractBlocked = _contractBlocklist(rules);
    expect(contractBlocked.length, greaterThanOrEqualTo(14),
        reason: 'اقتطاعُ قائمةِ العقودِ أخطأ (${contractBlocked.length})');
    final claimed = _notAnOrderFlag.entries
        .where((e) => e.value.contains('[contracts]'))
        .map((e) => e.key)
        .toSet();
    expect(claimed, isNotEmpty, reason: 'لا مُدخَلَ معلَّماً — الفحصُ أجوف');
    expect(claimed.difference(contractBlocked), isEmpty,
        reason: 'أُعفيَ بحجّةِ «حقلُ عقد» وهو غيرُ محجوبٍ هناك: '
            '${claimed.difference(contractBlocked)}');
  });
}
