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
  'has_active_subscription': 'حقلُ users',
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
};

String _stripJs(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// قائمةُ `hasAny([...])` في قاعدةِ إنشاءِ الطلب — **بموازنةِ الأقواس** لا
/// بأوّلِ `]`، وهو فخُّ الحدِّ المسجَّلُ في هذا المستودعِ مرّاتٍ.
/// (ويَرمي بدلَ `expect`: الاستخراجُ يَجري في نطاقِ `main` و`expect` هناك
/// غيرُ مشروعٍ — `OutsideTestException`، وهو فخٌّ مسجَّلٌ في هذا المستودع.)
Set<String> _createBlocklist(String rules) {
  final i = rules.indexOf('match /orders/{orderId}');
  if (i < 0) throw StateError('كتلةُ قاعدةِ الطلباتِ اختفت');
  final seg = rules.substring(i);
  final h = seg.indexOf('hasAny([');
  if (h < 0) throw StateError('قائمةُ المنعِ اختفت من قاعدةِ الإنشاء');
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
    final adm = File('lib/screens/admin/admin_order_details_screen.dart')
        .readAsStringSync();
    expect(adm.contains("updatePayload['reminder_sent'] = false"), isTrue,
        reason: 'تصفيرُ الإدارةِ عند تغييرِ الموعدِ زالَ — وهو `update` لا '
            '`create`، فالحجبُ لا يَمَسُّه');
  });
}
