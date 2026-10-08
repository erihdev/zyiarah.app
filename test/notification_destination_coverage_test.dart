// **كلُّ نوعِ إشعارٍ يَصلُ صندوقَ العميلةِ له وجهة — مُشتَقّاً من الخادم.**
//
// `NotifTarget.route` قاعدةُ الوجهة، و`notification_target_test` يَشدُّ أنّ
// كلَّ مسارٍ تُعيدُه مُعلَنٌ في `router.dart`. والسؤالُ الذي لم يَسألْه أحدٌ
// هو العكس: **أيُّ نوعٍ يُرسِلُه الخادمُ لا يَبلغُ وجهةً أصلاً؟**
//
// `categoryOf` تُصنّفُ بالمفرداتِ لا بقائمةٍ مغلقة — قرارٌ صحيحٌ (أنواعُ
// الخادمِ تَتغيّر) وثمنُه أنّ نوعاً بمفردةٍ جديدةٍ يَسقطُ على `other` ⇒
// `NofifDest.none` ⇒ **لا مسارَ ولا زرَّ إجراءٍ على البطاقة**، بصمتٍ تامّ:
// لا خطأَ بناءٍ ولا فحصٌ يَسقُط. وقد وقعَ: `appointment_reminder` — ويُطلَقُ
// **مرّتَين لكلِّ طلبٍ مدفوعٍ بلا شرطٍ آخر** (٢٤س ثمّ ساعتان) — ومعه
// `appointment_changed`، **بينما نقرُ إشعارِ FCM لِلإشعارِ نفسِه يَفتحُ
// الطلبَ صحيحاً**
// عبرَ `notifTargetFromData({'orderId': …})`: سطحانِ للإشعارِ الواحدِ
// بجوابَين.
//
// فالنطاقُ **مُشتَقٌّ من `functions/`** لا مكتوبٌ بيد: الوسيطُ الرابعُ لكلِّ
// `queuePush(` بموازنةِ الأقواس، ومعه `type:` في كلِّ كتابةٍ مباشرةٍ على
// `collection("notifications")`. ومجموعةُ ما لا وجهةَ له تُقابَلُ **كاملةً**
// بقائمةٍ مُعلَنةٍ لكلِّ مُدخَلٍ سببُه **وشاهدُ سببِه** — فنوعٌ جديدٌ بلا
// وجهةٍ يُراجَعُ يومَ كتابتِه، ومُدخَلٌ لم يَعُد يُرسَلُ يَسقطُ كذلك فلا
// تَتعفّنُ القائمة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/notification_item.dart';
import 'package:zyiarah/utils/notification_target.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// وحداتُ الخادمِ التي نَكتبُها — بلا `node_modules` وبلا `functions/test`.
///
/// الاستثناءانِ مقيسانِ لا مزاجيّان: `node_modules` بلا `queuePush(` واحدٍ
/// (فمسحُه كلفةٌ بلا مكسب)، و`functions/test/*.js` يَحملُه في أربعةِ ملفّاتٍ
/// **داخلَ تأكيداتِ حُرّاس** لا إرسالاً — فعدُّه يُلوّثُ المفردات.
///
/// وأرضيّةُ `sourcesIn` هنا **١ بقصد**: العدُّ قبلَ الترشيحِ يَشملُ آلافَ
/// ملفّاتِ `node_modules` فأيُّ أرضيّةٍ عليه عقيمة. فالأرضيّةُ الحقيقيّةُ
/// **بعدَ** الترشيحِ، أدناه.
List<File> functionModules({required int atLeast}) {
  final files = sourcesIn('functions', atLeast: 1, exts: const ['.js'])
      .where((f) =>
          !f.path.contains('node_modules') &&
          !f.path.contains('${Platform.pathSeparator}test'
              '${Platform.pathSeparator}'))
      .toList();
  if (files.length < atLeast) {
    throw StateError('مسحُ الحارس: وحداتُ الخادمِ ${files.length} '
        'والأرضيّةُ $atLeast — مسحٌ انحلَّ، والحارسُ بلا موضوع.');
  }
  return files;
}

/// وسائطُ النداءِ الذي قوسُه عند [open]، بموازنةِ الأقواسِ واحترامِ النصوص.
///
/// حدٌّ بعَدِّ الأحرفِ أو بأوّلِ `)` يَقفُ داخلَ `{orderId: doc.id}` أو داخلَ
/// قالبٍ نصّيٍّ فيه فاصلة — فخُّ الحدِّ المسجَّلُ في هذا المستودعِ اثنتَي
/// عشرةَ مرّة.
List<String> callArgs(String s, int open) {
  var depth = 0;
  var start = open + 1;
  final parts = <String>[];
  var i = open;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"' || c == '`') {
      final q = c;
      i++;
      while (i < s.length) {
        if (s[i] == r'\') {
          i += 2;
          continue;
        }
        if (s[i] == q) {
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) {
        parts.add(s.substring(start, i));
        return parts;
      }
    } else if (c == ',' && depth == 1) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
    i++;
  }
  throw StateError('لم تُوازَنْ أقواسُ النداءِ عند $open');
}

/// نصٌّ حرفيٌّ مفردٌ، أو `null` لتعبيرٍ آخر.
String? literal(String arg) {
  final m = RegExp('''^\\s*(?:"([^"]*)"|'([^']*)')\\s*\$''').firstMatch(arg);
  if (m == null) return null;
  return m.group(1) ?? m.group(2);
}

/// نوعٌ مُرسَلٌ، ومَن يَستقبلُه كما كُتبَ في المصدر.
class Sent {
  final String type;
  final String toUid;
  Sent(this.type, this.toUid);
}

({List<Sent> sent, List<String> nonLiteral, int calls}) scanQueuePush() {
  final sent = <Sent>[];
  final nonLiteral = <String>[];
  var calls = 0;
  for (final f in functionModules(atLeast: 15)) {
    final s = stripComments(f.readAsStringSync());
    for (final m in RegExp(r'\bqueuePush\s*\(').allMatches(s)) {
      calls++;
      final parts = callArgs(s, m.end - 1);
      if (parts.length < 4) {
        nonLiteral.add('<أقلُّ من أربعةِ وسائط>');
        continue;
      }
      final t = literal(parts[3]);
      if (t == null) {
        nonLiteral.add(parts[3].trim());
        continue;
      }
      sent.add(Sent(t, parts[0].trim()));
    }
  }
  return (sent: sent, nonLiteral: nonLiteral, calls: calls);
}

/// الأنواعُ في كتابةٍ مباشرةٍ على `notifications` (لا تَمُرُّ بالطابور).
Set<String> scanDirectInboxTypes() {
  final out = <String>{};
  for (final f in functionModules(atLeast: 15)) {
    final s = stripComments(f.readAsStringSync());
    for (final m
        in RegExp(r'collection\(\s*"notifications"\s*\)').allMatches(s)) {
      final open = s.indexOf('({', m.end);
      if (open < 0) continue;
      final body = callArgs(s, open).join(',');
      final t =
          RegExp('''\\btype\\s*:\\s*(?:"([^"]*)"|'([^']*)')''').firstMatch(body);
      if (t != null) out.add(t.group(1) ?? t.group(2)!);
    }
  }
  return out;
}

/// معرّفُ مستندِ طلبٍ واقعيّ (عشرونَ محرفاً من `.doc()`).
const orderDoc = 'kJ3nQ8pLm2Rv7Xy4Ab9C';

bool hasDestination(String type, {String? relatedId = orderDoc}) =>
    notifTargetFromRecord(type: type, relatedId: relatedId).route != null;

void main() {
  final q = scanQueuePush();
  final direct = scanDirectInboxTypes();
  final vocab = <String>{...q.sent.map((e) => e.type), ...direct};

  // مَن يَستقبلُ كلَّ نوع (للنوعِ أكثرُ من مُستقبِلٍ أحياناً).
  final recipients = <String, Set<String>>{};
  for (final e in q.sent) {
    recipients.putIfAbsent(e.type, () => <String>{}).add(e.toUid);
  }

  // ——— القائمةُ المُعلَنة: نوعٌ بلا وجهةٍ وسببُ أمانِه ———
  const adminBroadcastOnly = <String>{
    // بثٌّ إداريٌّ: `toUid == "ADMIN_BROADCAST"`، فلا مستندَ صندوقٍ يُنشَأُ
    // أصلاً — البوّابةُ `if (toUid && toUid !== "ADMIN_BROADCAST")`.
    'admin_deletion_failed',
    'admin_low_rating',
    'admin_price_review',
    'admin_price_tamper',
    'new_maintenance_admin',
  };
  const noInboxAtAll = <String>{
    // `queuePush(null, …)`: بريدٌ وحدَه، والبوّابةُ نفسُها تُسقِطُه.
    'email',
  };
  const driverOnly = <String>{
    // صندوقُ السائقِ لا يَفتحُ شيئاً لأيِّ نوع — نقرتُه تُعلّمُ مقروءاً
    // وحدَه. قصورُ سطحٍ أوسعُ من هذا النوع: مرفوعٌ لا مُغلَقٌ هنا.
    'task_reminder',
  };
  const deadTrigger = <String>{
    // `notifyClientOnMaintenanceRejected` مُشغّلٌ على `maintenance_requests`
    // و**لا كاتبَ فعّالاً للمجموعةِ في المستودعِ كلِّه**، فلا يُطلَقُ أبداً.
    'maintenance_rejected',
  };
  final declaredNoDestination = <String>{
    ...adminBroadcastOnly,
    ...noInboxAtAll,
    ...driverOnly,
    ...deadTrigger,
  };

  test('(أ) الاشتقاقُ يَقرأُ الخادمَ فعلاً — أرضيّةٌ لكلِّ مسح', () {
    expect(q.calls, greaterThanOrEqualTo(40),
        reason: 'نداءاتُ queuePush انحلَّت — الحارسُ بلا موضوع');
    expect(vocab.length, greaterThanOrEqualTo(25),
        reason: 'مفرداتُ الخادمِ انحلَّت — المقارنةُ تَصيرُ فارغةً فتَمُرّ');
    expect(direct.length, greaterThanOrEqualTo(2),
        reason: 'الكتاباتُ المباشرةُ على notifications انحلَّت');
    // الوسيطانِ غيرُ الحرفيَّين مُقاسانِ ومثبّتان: تمريرٌ من مُنادٍ أعلى،
    // فنوعُهما يَأتي من موضعِ النداءِ لا من هنا.
    expect(q.nonLiteral.toSet(), {'pushType', 'type'},
        reason: 'وسيطُ نوعٍ غيرُ حرفيٍّ ثالثٌ — يُراجَعُ بدلَ أن يَفلتَ من المسح');
  });

  test('(ب) الكاشفُ يَعضُّ — مُجرَّبٌ على الأشكالِ التي تُعميه', () {
    // المصدرُ بعدَ الإصلاحِ نظيفٌ، فنجاحُ المقارنةِ وحدَه لا يُبرهِنُ أنّ
    // المُستخرِجَ يَرى شيئاً.
    const synthetic = r'''
      await queuePush(d.client_id, `عنوان ${x}`, `نص, فيه فاصلة`,
          "synthetic_type", {orderId: doc.id, code: code});
      await queuePush(null, "ع", "ن", "synthetic_email", {orderId: oid});
      await queuePush(uid, "ع", "ن", pushType, {});
    ''';
    final seen = <String, String>{};
    final nonLit = <String>[];
    for (final m in RegExp(r'\bqueuePush\s*\(').allMatches(synthetic)) {
      final parts = callArgs(synthetic, m.end - 1);
      final t = literal(parts[3]);
      if (t == null) {
        nonLit.add(parts[3].trim());
      } else {
        seen[t] = parts[0].trim();
      }
    }
    expect(seen, {
      'synthetic_type': 'd.client_id',
      'synthetic_email': 'null',
    }, reason: 'الوسيطُ الرابعُ يُقرَأُ عبرَ قالبٍ نصّيٍّ وفاصلةٍ داخلَه');
    expect(nonLit, ['pushType']);

    // وحدٌّ غيرُ مُوازَنٍ كان سيَقفُ داخلَ `{orderId: …}`:
    final one = RegExp(r'\bqueuePush\s*\(').firstMatch(synthetic)!;
    expect(callArgs(synthetic, one.end - 1).length, 5,
        reason: 'الوسائطُ خمسةٌ — المعقوفةُ لا تُحسَبُ فاصلاً');

    // وتعليقٌ يَذكرُ نوعاً ليس إرسالاً:
    expect(stripComments('// queuePush(u, "ع", "ن", "ghost_type", {});'),
        isNot(contains('ghost_type')));
  });

  test('(ج) كلُّ نوعٍ يَصلُ صندوقَ العميلةِ له وجهةٌ — المجموعةُ كاملةً', () {
    final without = vocab.where((t) => !hasDestination(t)).toSet();
    expect(without, declaredNoDestination,
        reason: 'نوعٌ بلا وجهةٍ خارجَ القائمةِ = بطاقةٌ بلا مسارٍ ولا زرّ، '
            'ومُدخَلٌ صارت له وجهةٌ يُرفَعُ من القائمةِ لا يُسكَت');
    expect(declaredNoDestination.difference(vocab), isEmpty,
        reason: 'مُدخَلٌ لم يَعُدْ يُرسِلُه الخادمُ — القائمةُ تَتعفّن');
  });

  test('(د) ومجموعةُ ما لا وجهةَ له لا تَتبعُ relatedId', () {
    // الخادمُ يَكتبُ `relatedId: data.orderId || data.code || null`، فنوعٌ بلا
    // أيِّهما يَصلُ بـ`null` — ومع ذلك له مسارٌ («طلباتي») متى كان من مفرداتِ
    // الطلب. فالمجموعةُ واحدةٌ في الحالتَين، والحكمُ لا يَتعلّقُ بمثالٍ اخترتُه.
    final withId = vocab.where((t) => !hasDestination(t)).toSet();
    final withNull =
        vocab.where((t) => !hasDestination(t, relatedId: null)).toSet();
    expect(withNull, withId);
  });

  test('(هـ) شاهدُ البثِّ الإداريّ: البوّابةُ قائمةٌ وكلٌّ يُرسَلُ إليها', () {
    final idx = stripComments(File('functions/index.js').readAsStringSync());
    expect(idx, contains('if (toUid && toUid !== "ADMIN_BROADCAST")'),
        reason: 'بوّابةُ كتابةِ الصندوقِ هي سببُ الإعفاء — زوالُها يُراجِعُ '
            'القائمةَ كلَّها');
    for (final t in adminBroadcastOnly) {
      expect(recipients[t], {'"ADMIN_BROADCAST"'},
          reason: '«$t» صارَ يُرسَلُ إلى مستخدمٍ — فله صندوقٌ، فيَلزمُه وجهة');
    }
  });

  test('(و) شاهدُ البريدِ وحدَه: `email` بلا مُستقبِل', () {
    expect(recipients['email'], {'null'},
        reason: '`email` صارَ له مُستقبِلٌ — فله صندوقٌ، فيَلزمُه وجهة');
  });

  test('(ز) شاهدُ السائق: `task_reminder` له وحدَه، وصندوقُه لا يَنقُل', () {
    expect(recipients['task_reminder'], {'d.driver_id'},
        reason: '`task_reminder` صارَ يُرسَلُ للعميلةِ — فيَلزمُه وجهة');
    final drv = stripComments(
        File('lib/screens/driver_notifications_screen.dart').readAsStringSync());
    expect(drv, isNot(contains('notifTargetFromRecord')),
        reason: 'صندوقُ السائقِ صارَ يَقرأُ القاعدةَ — فالإعفاءُ يُراجَع');
    expect(drv.contains('context.push') || drv.contains('context.go'), isFalse,
        reason: 'صندوقُ السائقِ صارَ يَنقُل — فالإعفاءُ يُراجَع');
  });

  test('(ح) شاهدُ المُشغّلِ الميّت: `maintenance_requests` بلا كاتبٍ فعّال', () {
    final corpus = <File>[
      ...sourcesIn('lib', atLeast: 120),
      ...functionModules(atLeast: 15),
      ...sourcesIn('admin_panel/src', atLeast: 20, exts: const ['.ts', '.tsx']),
    ];
    final writes = <String>[];
    var midMentions = 0;
    for (final f in corpus) {
      final s = stripComments(f.readAsStringSync());
      midMentions += RegExp(r'\bmaintenance_id\b').allMatches(s).length;
      for (final m
          in RegExp('''['"]maintenance_requests['"]''').allMatches(s)) {
        final tail = s.substring(m.end, (m.end + 160).clamp(0, s.length));
        if (RegExp(r'\.(set|update|add|delete)\s*\(').hasMatch(tail) ||
            RegExp(r'\b(setDoc|updateDoc|addDoc|deleteDoc)\s*\(')
                .hasMatch(tail)) {
          writes.add('${f.path}: ${tail.split('\n').first.trim()}');
        }
      }
    }
    // الكتابتانِ الوحيدتانِ (`syncOrderLinkedRecords`) مشروطتانِ
    // بـ`after.maintenance_id` — **وذِكرُ الحقلِ في الشفرةِ كلِّها واحدٌ، وهو
    // تلك القراءةُ نفسُها**: لا كاتبَ له، فالفرعُ غيرُ قابلِ الوصول. فلا كاتبَ
    // يُنشئُ المجموعةَ ولا يُحدّثُها إلى `rejected`، فالمُشغّلُ لا يُطلَق.
    expect(writes.length, 2, reason: 'كاتبٌ ثالثٌ لـmaintenance_requests: '
        'المُشغّلُ قد يُطلَق، فيَلزمُ النوعَ وجهةٌ أو تعليلٌ آخر — $writes');
    expect(midMentions, 1,
        reason: 'ظهرَ كاتبٌ (أو قارئٌ ثانٍ) لـmaintenance_id — فالفرعُ صارَ '
            'قابلَ الوصولِ ويُراجَعُ التعليل');
  });

  test('(ط) الإصلاحُ: الموعدُ يَبلغُ تتبّعَ الطلبِ بزرٍّ ورقاقةٍ صحيحة', () {
    for (final t in ['appointment_reminder', 'appointment_changed']) {
      expect(vocab, contains(t), reason: 'الخادمُ ما زال يُرسِلُ «$t»');
      final target = notifTargetFromRecord(type: t, relatedId: orderDoc);
      expect(target.kind, NotifDest.order);
      expect(target.route, '/track/$orderDoc');
      expect(notifActionLabel(target, NotificationItem.categoryOf(t)),
          'تتبع الطلب');
      expect(NotificationItem.categoryOf(t), NotificationCategory.orders,
          reason: 'الرقاقةُ «الطلبات والميدان» لا «أخرى»');
    }
  });

  test('(ي) والسطحانِ يَتّفقانِ على الموعد — السجلُّ وحِملُ FCM', () {
    // العطلُ كان **اختلافَ سطحَين للإشعارِ الواحد**: حِملُ FCM يَحملُ
    // `{orderId}` فيَفتحُ الطلبَ، والسجلُّ يَسقطُ على «لا وجهة».
    for (final t in ['appointment_reminder', 'appointment_changed']) {
      expect(notifTargetFromRecord(type: t, relatedId: orderDoc),
          notifTargetFromData({'orderId': orderDoc}),
          reason: 'سطحانِ للإشعارِ الواحدِ بجوابَين');
    }
    // وشاهدُ الحِمل: الخادمُ ما زال يُرسِلُ `{orderId: …}` مع كلِّ إشعارِ موعد
    // — فبلاه يَقعُ السجلُّ على «طلباتي» وحِملُ FCM على «لا وجهة»، فيَفترِقان.
    var checked = 0;
    for (final f in functionModules(atLeast: 15)) {
      final s = stripComments(f.readAsStringSync());
      for (final m in RegExp(r'\bqueuePush\s*\(').allMatches(s)) {
        final parts = callArgs(s, m.end - 1);
        if (parts.length < 5) continue;
        final t = literal(parts[3]);
        if (t == null || !t.startsWith('appointment_')) continue;
        expect(parts[4], contains('orderId'));
        checked++;
      }
    }
    expect(checked, 4,
        reason: 'أربعةُ مواضعِ إرسالٍ لإشعاراتِ الموعد: تذكيرانِ للعميلة '
            '(٢٤س وساعتان) وتغييرُ موعدٍ لها ونسخةٌ للسائق — تغيّرُ العددِ '
            'يُراجَع');
  });
}
