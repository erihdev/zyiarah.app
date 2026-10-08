// حارسُ **وجهةِ الإشعار: قاعدةٌ واحدةٌ لثلاثةِ قُرّاء**.
//
// ═══ العطل ═══
//
// «أين يَذهبُ هذا الإشعارُ؟» كان مكتوباً ثلاثَ مرّاتٍ ولا يَتّفق:
// `_routeFor` (المسار) و`_actionLabelFor` (**النصُّ المرئيُّ** على البطاقة) في
// `client_notifications_screen`، و`handleNotificationTap` (نقرُ FCM) في
// `deep_link_service`. فالنتيجةُ **وجهةٌ خاطئةٌ تحتَ نصٍّ يَعِدُ بغيرِها**، لا
// صمتاً:
//
//   • `categoryOf` تُصنّفُ كلَّ نوعٍ فيه `contract` ضمنَ `payments`؛
//   • والخادمُ كان يَكتبُ `relatedId: data.orderId || data.code ||
//     event.params.id`، وإشعارُ العقدِ لا يَحملُ أيَّهما — فيَقعُ على
//     **معرّفِ مستندِ الطابور**: عشرونَ محرفاً لا يَبدأُ بـ`ZY-` ولا
//     بـ`trig_`، فـ`relatedLooksLikeOrderDoc` تَقولُ «نعم»؛
//   • فبطاقةُ «تم تفعيل باقتك» كانت تَعرضُ **«عرض الطلب والفاتورة»** وتَذهبُ
//     إلى `/track/<معرّفِ الطابور>`: شاشةُ تتبّعِ طلبٍ لا وجودَ له.
//
// **مُثبَتٌ باختبارِ واجهةٍ على الشاشةِ نفسِها قبل الإصلاح**، لا بالقراءة:
// النقرُ أعطى `/track/kJ3nQ8pLm2Rv7Xy4Ab9C` مرّتَين.
//
// والطرفُ الآخر: «تم الرد على تذكرتك 💬» — `support_ticket` لا يُطابِقُ أيَّ
// مفردةٍ في `categoryOf` فيَقعُ في `other` ⇒ **لا مسارَ ولا نصَّ زرّ**؛ ونقرُ
// إشعارِ FCM له يُنتجُ `zyiarah://app/ticket/<id>` وفرعُ التذكرةِ في
// `_handleUri` كان **محصوراً بالإدارة** — فالردُّ الذي طلبَته العميلةُ لا
// يُفتَحُ من أيِّ سطحٍ من الاثنَين.
//
// ونتيجةٌ سالبةٌ تُسجَّلُ كما هي: `referral_coupon` كان **صحيحاً** —
// `categoryOf` تَفحصُ `offers` أوّلاً و`coupon` فيه، فذهبَ إلى `/offers`.
// ظننتُه معطوباً فأثبتَ الاختبارُ خلافَ ظنّي، والفحصُ يُثبّتُه كي لا يَكسِرَه
// «إصلاح».
//
// ═══ الحارس ═══
//
// يَفحصُ القاعدةَ **سلوكاً** (دالّةٌ خالصة)، ثمّ يَشدُّ القُرّاءَ الثلاثةَ
// إليها نصّاً، ثمّ يُثبِتُ أنّ المسارَين الجديدَين (`/contracts`, `/support`)
// مُعلَنانِ في `router.dart` — فقاعدةٌ تُعيدُ مساراً لا يَعرفُه `go_router`
// لا تَنقُلُ أحداً. ومجموعةُ مفاتيحِ الوجهاتِ **مُشتَقّةٌ من الخادم**، فمفتاحٌ
// خامسٌ يُراجَعُ بدلَ أن يُرسَلَ إلى عميلٍ لا يَعرفُه.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/notification_item.dart';
import 'package:zyiarah/screens/client_notifications_screen.dart';
import 'package:zyiarah/utils/notification_target.dart';

import 'helpers/strip_comments.dart';

/// معرّفُ مستندِ طابورٍ تلقائيٌّ — ما كان الخادمُ يَضَعُه في `relatedId`.
const String _queueId = 'kJ3nQ8pLm2Rv7Xy4Ab9C';
const String _orderDoc = 'AbCdEfGhIjKlMnOpQrSt';

String _strip(String src) => src
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');


/// مقاطعُ نداءٍ على العمقِ صفر، **مع احترامِ الاقتباسات** — وهذا ليس
/// تجميلاً: أوّلُ صياغةٍ أخذت أوّلَ `{` في النداء، وهو في معظمِ المواضعِ
/// `${…}` داخلَ قالبٍ نصّيٍّ لا كائنَ البيانات، فأبلغت عن «مفاتيحَ» مثل
/// `code` و`greet` و`points` لا وجودَ لها. والحدُّ بموازنةِ الأقواسِ لا
/// بأوّلِ محرفٍ مطابق — فخُّ الحدِّ المسجَّلُ في هذا المستودعِ مرّاتٍ.
List<String> _callArgs(String call) {
  final out = <String>[];
  final buf = StringBuffer();
  int depth = 0;
  String? quote;
  for (int i = 0; i < call.length; i++) {
    final c = call[i];
    if (quote != null) {
      buf.write(c);
      if (c == r'\') {
        if (i + 1 < call.length) buf.write(call[++i]);
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'" || c == '`') {
      quote = c;
      buf.write(c);
      continue;
    }
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ',' && depth == 0) {
      out.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  final last = buf.toString().trim();
  if (last.isNotEmpty) out.add(last);
  return out;
}

/// مفاتيحُ كائنٍ حرفيٍّ — المُعرِّفُ في **موضعِ المفتاح** من كلِّ مقطع، فلا
/// تُبتلَعُ القيمُ (`{requestId: reqId}` كان يُعطي `reqId` أيضاً).
Set<String> _objectKeys(String obj) {
  final t = obj.trim();
  if (!t.startsWith('{')) return <String>{};
  final inner = t.substring(1, t.length - 1);
  final keys = <String>{};
  for (final seg in _callArgs(inner)) {
    final m = RegExp(r'^([A-Za-z_$][A-Za-z0-9_$]*)\s*(?::|$)').firstMatch(seg);
    if (m != null) keys.add(m.group(1)!);
  }
  return keys;
}

/// أعضاءُ تعدادٍ بالاسم. يُشتَقُّ ليُقابَلَ بأرماءِ المُبدِّلات: فعضوٌ جديدٌ
/// بلا رَماءٍ خطأُ ترجمةٍ في دارت — ما لم يُكتَبْ رَماءٌ شامل، وذاك ما
/// يَمنعُه `_enumSwitchArms` برميِه.
Set<String> _enumMembers(String src, String name) {
  final a = src.indexOf('enum $name ');
  if (a < 0) throw StateError('تعدادُ «$name» لم يُوجَد');
  final open = src.indexOf('{', a);
  if (open < 0) throw StateError('لا جسمَ لتعدادِ «$name»');
  final body = _balanced(src, open, 'تعدادِ «$name»');
  return _splitTopLevel(body)
      .map((seg) =>
          RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)').firstMatch(seg)?.group(1))
      .whereType<String>()
      .toSet();
}

/// جسمُ كتلةٍ **بموازنةِ الأقواس** من `{` المُعطى — لا عدَّ أحرفٍ ولا أوّلَ
/// `}`: فخُّ الحدِّ غيرِ المُوازَنِ أسقطَ حُرّاساً في هذا المستودعِ مرّاتٍ.
String _balanced(String src, int open, String what) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '{' || c == '(' || c == '[') depth++;
    if (c == '}' || c == ')' || c == ']') {
      depth--;
      if (depth == 0) return src.substring(open + 1, i);
    }
  }
  throw StateError('لم تُوازَنْ أقواسُ $what');
}

/// تقسيمُ مقاطعَ على فواصلِ **العمقِ صفر** مع احترامِ النصوص — فتعبيرٌ فيه
/// فاصلةٌ (`NotifTarget(X, id: y)`) لا يُقطَعُ نصفَين.
List<String> _splitTopLevel(String body) {
  final segs = <String>[];
  var buf = StringBuffer();
  var depth = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == "'" || c == '"') {
      final q = c;
      buf.write(c);
      i++;
      while (i < body.length) {
        if (body[i] == r'\' && i + 1 < body.length) {
          buf.write(body.substring(i, i + 2));
          i += 2;
          continue;
        }
        buf.write(body[i]);
        if (body[i] == q) break;
        i++;
      }
      continue;
    }
    if (c == '{' || c == '(' || c == '[') depth++;
    if (c == '}' || c == ')' || c == ']') depth--;
    if (c == ',' && depth == 0) {
      segs.add(buf.toString());
      buf = StringBuffer();
      continue;
    }
    buf.write(c);
  }
  segs.add(buf.toString());
  return segs.where((s) => s.trim().isNotEmpty).toList();
}

/// أرماءُ `switch` تعبيريٍّ على عضوِ تعداد: المفتاحُ العضوُ والقيمةُ نصُّ
/// التعبيرِ كما هو.
///
/// يَرمي على رَماءٍ لا يُقرأُ — ومنه **الرَّماءُ الشاملُ** (`_ =>`): وجودُه
/// يُبطِلُ شموليّةَ المُبدِّلِ، وهي وحدَها ما يَجعلُ عضواً جديداً خطأَ
/// ترجمةٍ بدلَ وجهةٍ صامتةٍ تَسقطُ إلى `null`.
Map<String, String> _enumSwitchArms(String src, String anchor, String enumName) {
  final a = src.indexOf(anchor);
  if (a < 0) throw StateError('مِرساةُ «$anchor» لم تُوجَد');
  final open = src.indexOf('{', a);
  if (open < 0) throw StateError('لا جسمَ لـ«$anchor»');
  final body = _balanced(src, open, '«$anchor»');
  final re = RegExp(
      '^\\s*$enumName\\.([A-Za-z_][A-Za-z0-9_]*)\\s*=>\\s*([\\s\\S]*)\$');
  final arms = <String, String>{};
  for (final seg in _splitTopLevel(body)) {
    final m = re.firstMatch(seg);
    if (m == null) {
      throw StateError('رَماءٌ لا يُقرأُ في «$anchor»: ${seg.trim()}');
    }
    arms[m.group(1)!] = m.group(2)!.trim();
  }
  return arms;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  NotifTarget rec(String type, {String? related}) =>
      notifTargetFromRecord(type: type, relatedId: related);

  String? label(String type, {String? related}) => notifActionLabel(
      rec(type, related: related), NotificationItem.categoryOf(type));

  // ── (١) العطلُ نفسُه: إشعارُ العقدِ لا يَدّعي طلباً ───────────────────
  test('إشعارُ العقدِ يَذهبُ إلى «عقودي» لا إلى تتبّعِ طلبٍ لا وجودَ له', () {
    for (final t in const ['contract_activated', 'contract_visits_scheduled']) {
      final target = rec(t, related: _queueId);
      expect(target.kind, NotifDest.contracts, reason: '$t: الوجهةُ خاطئة');
      expect(target.route, '/contracts', reason: '$t: المسارُ خاطئ');
      expect(target.route, isNot(contains('/track/')),
          reason: '$t: عادَ إلى شاشةِ تتبّعِ طلبٍ لا وجودَ له');
      expect(label(t, related: _queueId), 'عقودي',
          reason: '$t: النصُّ يَعِدُ بغيرِ ما يَفعلُه النقر');
      expect(label(t, related: _queueId), isNot('عرض الطلب والفاتورة'));
    }
    // `contract_visits_scheduled` يَحملُ `visit` كذلك، و`categoryOf` تَقرؤها
    // `orders` — فالعقدُ يَسبقُ عمداً، وانقلابُ الأسبقيّةِ يُعيدُ العطل.
    expect(
        NotificationItem.categoryOf('contract_visits_scheduled'),
        NotificationCategory.payments,
        reason: 'التصنيفُ تغيّر — راجِعْ أسبقيّةَ العقدِ في القاعدة');
  });

  // ── (٢) والردُّ على التذكرةِ صارَ له وجهة ──────────────────────────────
  test('«تم الرد على تذكرتك» يَفتحُ الدعمَ بعد أن كان بلا وجهةٍ ولا زرّ', () {
    final target = rec('support_ticket', related: _queueId);
    expect(target.kind, NotifDest.support);
    expect(target.route, '/support');
    expect(label('support_ticket', related: _queueId), 'الدعم والمساعدة',
        reason: 'كان null — بطاقةٌ بلا زرٍّ لأكثرِ إشعارٍ معناه «تعالي اقرئي»');
  });

  // ── (٣) وما كان صحيحاً يَبقى — بما فيه ما ظننتُه معطوباً ──────────────
  test('الوجهاتُ القائمةُ محفوظةٌ حرفاً', () {
    expect(rec('order_update', related: _orderDoc).route, '/track/$_orderDoc');
    expect(label('order_update', related: _orderDoc), 'تتبع الطلب');
    expect(rec('payment_update', related: _orderDoc).route, '/track/$_orderDoc');
    expect(label('payment_update', related: _orderDoc), 'عرض الطلب والفاتورة',
        reason: 'صياغةٌ قائمةٌ: إشعارُ الدفعِ يُسمّي الفاتورةَ لا التتبّع');
    // كودُ طلبٍ ليس مستندَ طلب ⇒ «طلباتي».
    expect(rec('order_assignment', related: 'ZY-202600042').route, '/orders');
    expect(label('order_assignment', related: 'ZY-202600042'), 'طلباتي');
    expect(rec('global_broadcast').route, '/offers');
    expect(label('global_broadcast'), 'العروض');
    // **نتيجةٌ سالبةٌ مثبَّتة**: هذا كان صحيحاً قبل الإصلاحِ وأثبتَه الاختبار.
    expect(rec('referral_coupon', related: _queueId).route, '/offers',
        reason: 'كوبونُ الإحالةِ كان يَذهبُ للعروضِ بحقٍّ — لا تَكسِرْه');
    expect(rec('order_rated_thanks_unknown_type').kind, isNot(NotifDest.none),
        reason: 'نوعٌ فيه order يَبقى طلباً');
  });

  // ── (٤) ومن حِملِ FCM: المفاتيحُ وترتيبُها ────────────────────────────
  test('حِملُ FCM: مفاتيحُ الوجهاتِ وترتيبُ تحديدِها', () {
    expect(notifTargetFromData({'orderId': 'o1'}),
        const NotifTarget(NotifDest.order, id: 'o1'));
    expect(notifTargetFromData({'ticketId': 't1'}),
        const NotifTarget(NotifDest.support, id: 't1'));
    expect(notifTargetFromData({'requestId': 'r1'}),
        const NotifTarget(NotifDest.maintenance, id: 'r1'));
    expect(notifTargetFromData({'contractId': 'c1'}),
        const NotifTarget(NotifDest.contracts, id: 'c1'),
        reason: 'كان لا يُقرأُ إطلاقاً — فنقرُ إشعارِ العقدِ لا يَفعلُ شيئاً');
    // بثٌّ عامٌّ أو قيمٌ فارغةٌ ⇒ يَبقى في مكانِه (لا تنقّلٌ أعمى).
    expect(notifTargetFromData({}).kind, NotifDest.none);
    expect(notifTargetFromData({'contractId': '  '}).kind, NotifDest.none);
    expect(notifTargetFromData({'orderId': null, 'contractId': 'c1'}).kind,
        NotifDest.contracts);
    // الأسبقيّةُ كترتيبِ التعدادِ القديمِ بعينِه.
    expect(
        notifTargetFromData({'orderId': 'o', 'ticketId': 't', 'contractId': 'c'})
            .kind,
        NotifDest.order);
  });

  // ── (٥) القُرّاءُ الثلاثةُ يَسألونها، ولا تعدادَ محلّيّاً باقياً ───────
  test('قاعدةٌ واحدةٌ: الشاشةُ والخدمةُ تُناديانِها ولا تُعيدانِ كتابتَها', () {
    final screen = _strip(
        File('lib/screens/client_notifications_screen.dart').readAsStringSync());
    expect(screen.contains('notifTargetFromRecord('), isTrue,
        reason: 'المسارُ لم يَعُد من القاعدة');
    expect(screen.contains('notifActionLabel('), isTrue,
        reason: 'النصُّ لم يَعُد من القاعدة');
    for (final gone in const [
      "'/track/\${n.relatedId}'",
      "case NotificationCategory.offers:",
    ]) {
      expect(screen.contains(gone), isFalse,
          reason: 'تعدادٌ محلّيٌّ عادَ إلى الشاشة («$gone») — والثلاثةُ '
              'تَنحرِفُ ما لم تَسألْ مصدراً واحداً');
    }

    final svc =
        _strip(File('lib/services/deep_link_service.dart').readAsStringSync());
    expect(svc.contains('notifTargetFromData('), isTrue,
        reason: 'نقرُ FCM لم يَعُد من القاعدة');
    for (final gone in const ["data['orderId']", "data['ticketId']"]) {
      expect(svc.contains(gone), isFalse,
          reason: 'الخدمةُ عادت تَقرأُ المفاتيحَ بنفسِها («$gone»)');
    }
    // وفرعا العقدِ والتذكرةِ العميليّةِ قائمان.
    expect(svc.contains("resource == 'contract'"), isTrue,
        reason: 'لا فرعَ للعقدِ — فالرابطُ يُبنى ولا يُستقبَل');
    expect(svc.contains('ZyiarahSupportScreen()'), isTrue,
        reason: 'العميلةُ لا تَصلُ ردَّ تذكرتِها');
  });

  // ── (٦) وكلُّ مسارٍ تُعيدُه القاعدةُ مُعلَنٌ في go_router ──────────────
  //
  // **كان هذا الفحصُ زوجاً مكتوباً بيدٍ** (`/contracts`, `/support`) ونصُّه
  // عامٌّ: «القاعدةُ تُعيدُ $path ولا يَعرفُه go_router — نقرٌ بلا نقل».
  // والقاعدةُ تُعيدُ **خمسةَ** مسارات، فثلاثةٌ منها — ومنها `/track/$id`
  // المُعامَلُ — كانت خارجَ النظر. فالنطاقُ مُشتَقٌّ من أرماءِ المُبدِّلِ
  // نفسِه: مسارٌ سادسٌ يَدخلُ الفحصَ بنفسِه.
  test('(٦) كلُّ مسارٍ تُعيدُه القاعدةُ مُعلَنٌ في go_router', () {
    final rule = stripComments(
        File('lib/utils/notification_target.dart').readAsStringSync());
    final members = _enumMembers(rule, 'NotifDest');
    expect(members.length, greaterThanOrEqualTo(7),
        reason: 'انحلَّ استخراجُ أعضاءِ التعداد — فالمقارنةُ بلا موضوع');

    final arms = _enumSwitchArms(rule, 'String? get route', 'NotifDest');
    expect(arms.keys.toSet(), members,
        reason: 'المُبدِّلُ لا يُغطّي التعدادَ — ولو كان فيه رَماءٌ شاملٌ '
            'لَرَمى الاستخراجُ: الشموليّةُ هي ما يَجعلُ عضواً جديداً خطأَ '
            'ترجمةٍ لا وجهةً صامتة');

    final routes = <String, String>{};
    final silent = <String>{};
    arms.forEach((kind, expr) {
      if (expr == 'null') {
        silent.add(kind);
        return;
      }
      final m = RegExp(r"^'([^']*)'$").firstMatch(expr);
      expect(m, isNotNull,
          reason: 'رَماءُ $kind ليس نصّاً حرفيّاً («$expr») — فالفحصُ لا '
              'يَستطيعُ مُقابلتَه بـrouter.dart');
      routes[kind] = m!.group(1)!;
    });
    expect(routes.length, greaterThanOrEqualTo(5),
        reason: 'انحلَّ استخراجُ المسارات — حارسٌ أخضرُ أجوف');

    final r = stripComments(File('lib/router.dart').readAsStringSync());
    final declared = RegExp(r"path:\s*'([^']*)'")
        .allMatches(r)
        .map((m) => m.group(1)!)
        .toSet();
    expect(declared.length, greaterThanOrEqualTo(10),
        reason: 'انحلَّ استخراجُ مساراتِ go_router');

    routes.forEach((kind, route) {
      final dollar = route.indexOf(r'$');
      if (dollar < 0) {
        expect(declared, contains(route),
            reason: 'القاعدةُ تُعيدُ $route ($kind) ولا يَعرفُه go_router — '
                'نقرٌ بلا نقل');
        return;
      }
      // مسارٌ بمُعامَل: البادئةُ الساكنةُ ثمّ مقطعُ `:param` — فالمُقابَلةُ
      // بالشكلِ لا بالنصّ، وإلّا لَقُرئَ `/track/$id` غيرَ مُعلَنٍ أبداً.
      final prefix = route.substring(0, dollar);
      expect(prefix.endsWith('/'), isTrue,
          reason: '$kind: الاستقراءُ في منتصفِ مقطعٍ («$route») — '
              'لا يُقابَلُ بمسارٍ مُعامَلٍ');
      final shape = RegExp('^${RegExp.escape(prefix)}:[A-Za-z_][A-Za-z0-9_]*\$');
      expect(declared.any(shape.hasMatch), isTrue,
          reason: 'القاعدةُ تُعيدُ $route ($kind) ولا مسارَ مُعامَلٍ بشكلِ '
              '«$prefix:param» في go_router — نقرٌ بلا نقل');
    });

    // ومجموعةُ ما لا مسارَ له كاملةً، لكلٍّ سببُه: الصيانةُ أرشيفٌ إداريٌّ
    // (القواعدُ تَمنعُ العميلةَ من قراءةِ `maintenance_requests`)، و`none`
    // هي «يَبقى في مكانِه». فعضوٌ ثالثٌ يَسقطُ إلى `null` يُراجَعُ بوعي.
    expect(silent, {'maintenance', 'none'},
        reason: 'وجهةٌ بلا مسارٍ لم تُعلَّلْ — أو عُلّةٌ بائتةٌ بقيت');

    // وشاهدا التعليل: المسارانِ اللذانِ أُضيفا للقاعدةِ يَبنيانِ شاشتَيهما.
    expect(r.contains('ZyiarahContractsListScreen('), isTrue);
    expect(r.contains('ZyiarahSupportScreen('), isTrue);
  });

  // ── (٧) والخادمُ لا يَختَرعُ معرّفَ طلبٍ ──────────────────────────────
  test('relatedId لا يَقعُ على معرّفِ مستندِ الطابور', () {
    final raw = File('functions/index.js').readAsStringSync();
    final idx = _strip(raw)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');
    expect(idx.contains('relatedId: data.orderId || data.code || null'), isTrue,
        reason: 'البديلُ المُختَرَعُ عاد — ومعه `/track/<معرّفِ الطابور>`');
    expect(idx.contains('data.code || event.params.id'), isFalse,
        reason: 'الشكلُ القديمُ عادَ في مكانٍ ما');
    // المضادّة: التعليقُ يَشرحُ القرارَ بذكرِ الشكلِ القديم، فلو أكلَ
    // التجريدُ كلَّ شيءٍ لَمَرَّ الفحصُ أعلاه على فراغ.
    expect(raw.contains('event.params.id'), isTrue,
        reason: 'الاسمُ زالَ من الخامِّ — فالفحصُ السالبُ بلا موضوع');
  });

  // ── (٨) والحقلُ الميّتُ زال، والمعرّفُ يُكتَبُ في الجهتَين ────────────
  test('deepLink الميّتُ زالَ، وكلا المُحرِّرَين يَكتبُ contractId', () {
    final dart = _strip(
        File('lib/services/zyiarah_messaging_service.dart').readAsStringSync());
    final panel =
        _strip(File('admin_panel/src/pages/Contracts.tsx').readAsStringSync());
    for (final e in [
      ('خدمةُ الرسائل', dart),
      ('لوحةُ الويب', panel),
    ]) {
      expect(e.$2.contains('deepLink'), isFalse,
          reason: '${e.$1}: `deepLink` حقلٌ لا يَقرؤه أحد — '
              'وقيمتُه بلا معرّفٍ يَرفضُها `_handleUri` مرّتَين');
      expect(e.$2.contains('contractId'), isTrue,
          reason: '${e.$1}: لا معرّفَ عقدٍ في الحِمل — فالنقرُ بلا وجهة');
    }
  });

  // ── (٩) ومجموعةُ مفاتيحِ الوجهاتِ مُشتَقّةٌ من الخادم ─────────────────
  //
  // مفتاحٌ خامسٌ يُسمّي وجهةً ولا تَقرؤه القاعدةُ = إشعارٌ آخرُ بلا وجهة.
  test('كلُّ مفتاحِ وجهةٍ يَكتبُه الخادمُ تَقرؤه القاعدة', () {
    final rule = File('lib/utils/notification_target.dart').readAsStringSync();
    final read = RegExp(r"s\('([A-Za-z]+)'\)")
        .allMatches(rule)
        .map((m) => m.group(1)!)
        .toSet();
    expect(read.length, greaterThanOrEqualTo(4),
        reason: 'لم تُقرأ مفاتيحُ القاعدة — الاستخراجُ أخطأ');

    final written = <String>{};
    for (final f in Directory('functions')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))) {
      final src = _strip(f.readAsStringSync());
      for (final m in RegExp(r'\bqueuePush\(').allMatches(src)) {
        int depth = 1, j = m.end;
        while (j < src.length && depth > 0) {
          if (src[j] == '(') depth++;
          if (src[j] == ')') depth--;
          j++;
        }
        final call = src.substring(m.end, j - 1);
        // الوسيطُ **الخامسُ** هو كائنُ البيانات (`queuePush(toUid, title,
        // body, type, data, …)`) — ويُؤخَذُ بمقاطعِ العمقِ صفرٍ لا بأوّلِ
        // `{`، لأنّ العنوانَ والنصَّ قوالبُ فيها `${…}`.
        final args = _callArgs(call);
        if (args.length < 5) continue;
        written.addAll(_objectKeys(args[4])
            .where((k) => k.endsWith('Id') || k.endsWith('Uid')));
      }
    }
    // ما يُسمّي وجهةً فعلاً: ما تَعرفُه القاعدةُ + ما نُقِرُّ أنّه ليس وجهة.
    const notADestination = {
      // لا شاشةَ وجهةٍ لهما: أحدُهما سائقٌ في تنبيهٍ إداريٍّ، والآخرُ
      // مُعرِّفُ المُحال في تنبيهِ فشلِ إحالة — كلاهما سياقٌ لا مَقصد.
      'driverId', 'refereeUid', 'clientId', 'userId', 'toUid',
    };
    final unknown = written.difference(read).difference(notADestination);
    expect(unknown, isEmpty,
        reason: 'مفاتيحُ وجهةٍ يَكتبُها الخادمُ ولا تَقرؤها القاعدةُ: '
            '$unknown — إشعارٌ بلا وجهةٍ من جديد');
    expect(written.contains('orderId') && written.contains('contractId'),
        isTrue,
        reason: 'المسحُ لم يَجِدْ المفاتيحَ المعروفة — الاستخراجُ أخطأ');
  });

  // ── (١٠) والبرهانُ على الشاشةِ نفسِها، لا على الدالّةِ وحدَها ─────────
  testWidgets('البطاقةُ تَنقلُ إلى /contracts و/support على الشاشةِ الحقيقيّة',
      (t) async {
    NotificationItem n(String id, String type) => NotificationItem(
          id: id,
          title: 'عنوان $id',
          body: 'نصّ $id',
          type: type,
          createdAt: DateTime.now(),
          isRead: false,
          relatedId: _queueId,
        );
    final routes = <String>[];
    await t.pumpWidget(MaterialApp(
      home: ClientNotificationsScreen(
        items: Stream.value([
          n('c1', 'contract_activated'),
          n('st', 'support_ticket'),
        ]),
        uid: 'u1',
        markRead: (_) async {},
        navigate: (_, r) => routes.add(r),
      ),
    ));
    await t.pump();
    await t.pump();

    expect(find.text('عقودي'), findsOneWidget,
        reason: 'زرُّ العقدِ غائبٌ عن البطاقة');
    expect(find.text('الدعم والمساعدة'), findsOneWidget,
        reason: 'بطاقةُ التذكرةِ ما زالت بلا زرّ');
    expect(find.text('عرض الطلب والفاتورة'), findsNothing,
        reason: 'البطاقةُ ما زالت تَعِدُ بطلبٍ وفاتورة');

    await t.tap(find.text('عنوان c1'));
    await t.pump();
    await t.tap(find.text('عنوان st'));
    await t.pump();
    expect(routes, ['/contracts', '/support'],
        reason: 'النقرُ على الشاشةِ الحقيقيّةِ لم يَنقُلْ إلى الوجهتَين');
  });
  // ── (١١) وكلُّ موردٍ يُنتجُه نقرُ FCM له فرعٌ في `_handleUri` ───────────
  //
  // النصفُ الثاني من العطلِ نفسِه، من الجهةِ الأخرى: `handleNotificationTap`
  // يُحوّلُ الوجهةَ إلى **اسمِ مورد** ثمّ يَبني `zyiarah://app/<مورد>/<id>`
  // ويُسلّمُه إلى `_handleUri` — ولا شيءَ كان يُقابِلُ المجموعتَين. وهذا
  // بعينُه ما وقعَ من قبل: حقلُ `deepLink` كان يَحملُ
  // `zyiarah://app/contracts` فيَرفُضُه `_handleUri` مرّتَين (بلا معرّفٍ،
  // وبلا فرعٍ لذلك المورد) — رابطٌ يُبنى ويُرفَضُ بصمت.
  //
  // المجموعتانِ متّفقتانِ اليومَ، فهذا سدُّ ثغرةِ حارسٍ لا إصلاحُ عطل.
  test('(١١) مواردُ نقرِ FCM = فروعُ _handleUri', () {
    final svc =
        stripComments(File('lib/services/deep_link_service.dart').readAsStringSync());
    final members = _enumMembers(
        stripComments(File('lib/utils/notification_target.dart').readAsStringSync()),
        'NotifDest');
    final arms =
        _enumSwitchArms(svc, 'final String? resource = switch', 'NotifDest');
    expect(arms.keys.toSet(), members,
        reason: 'مُبدِّلُ الموردِ لا يُغطّي التعدادَ — ووجهةٌ جديدةٌ بلا '
            'رَماءٍ تَسقطُ صامتةً لو كان فيه رَماءٌ شامل');

    final produced = <String>{};
    final silent = <String>{};
    arms.forEach((kind, expr) {
      if (expr == 'null') {
        silent.add(kind);
        return;
      }
      final m = RegExp(r"^'([^']*)'$").firstMatch(expr);
      expect(m, isNotNull, reason: 'رَماءُ $kind ليس نصّاً حرفيّاً: $expr');
      produced.add(m!.group(1)!);
    });
    expect(produced.length, greaterThanOrEqualTo(4),
        reason: 'انحلَّ استخراجُ الموارد — حارسٌ أخضرُ أجوف');

    final handled = RegExp(r"resource == '([^']*)'")
        .allMatches(svc)
        .map((m) => m.group(1)!)
        .toSet();
    expect(handled.length, greaterThanOrEqualTo(4),
        reason: 'انحلَّ استخراجُ فروعِ `_handleUri`');

    // الاتّجاهانِ معاً: موردٌ يُبنى بلا فرعٍ = رابطٌ يُرفَضُ بصمت، وفرعٌ لا
    // يُنتجُه أحدٌ = شفرةٌ ميّتةٌ أو وجهةُ رابطٍ خارجيٍّ — وكلاهما يُراجَع.
    expect(produced, handled,
        reason: 'افترقت مجموعةُ الموارِدِ المبنيّةِ عن مجموعةِ الفروع');

    // ومجموعةُ ما لا موردَ له كاملةً: `orders` و`offers` قائمتانِ بلا
    // معرّفٍ (لا شاشةَ تُفتَحُ بمعرّف)، و`none` لا وجهةَ لها أصلاً.
    expect(silent, {'orders', 'offers', 'none'},
        reason: 'وجهةٌ بلا موردٍ لم تُعلَّلْ — أو عُلّةٌ بائتةٌ بقيت');
  });

  // ── (١٢) والكاشفُ يُختبَرُ كالشفرة ─────────────────────────────────────
  //
  // المصدرُ بعدَ الإصلاحِ نظيفٌ، فنجاحُ (٦) و(١١) وحدَه لا يُبرهِنُ أنّ
  // المُستخرِجَ يَرى رَماءً أصلاً.
  test('(١٢) المُستخرِجُ يَرى الأرماءَ ولا يَرى تعليقاً ولا يَقطعُ تعبيراً', () {
    const real = '''
enum D { a, b }
String? get route => switch (kind) {
      D.a => '/x/\$id',
      // D.b => '/معلّق',
      D.b => null,
    };
''';
    final stripped = stripComments(real);
    expect(_enumMembers(stripped, 'D'), {'a', 'b'});
    expect(_enumSwitchArms(stripped, 'String? get route', 'D'),
        {'a': "'/x/\$id'", 'b': 'null'},
        reason: 'إمّا لم يُرَ رَماءٌ، أو قُرئَ التعليقُ رَماءً');

    // فاصلةٌ داخلَ تعبيرٍ لا تَقطعُ الرَّماءَ نصفَين.
    const nested = '''
X? get r => switch (k) {
      D.a => Y(D.a, id: z),
      D.b => null,
    };
''';
    expect(_enumSwitchArms(stripComments(nested), 'X? get r', 'D')['a'],
        'Y(D.a, id: z)');

    // ورَماءٌ شاملٌ يُسقِطُ الاستخراجَ بدلَ أن يُبتلَع — وهو ما يُبقي
    // شموليّةَ المُبدِّلِ حارساً عند الترجمة.
    const wild = '''
X? get r => switch (k) {
      D.a => 1,
      _ => null,
    };
''';
    expect(() => _enumSwitchArms(stripComments(wild), 'X? get r', 'D'),
        throwsStateError);

    // ومِرساةٌ غائبةٌ أو أقواسٌ غيرُ مُوازَنةٍ تَرمي، فلا تُقرأُ «نظيفة».
    expect(() => _enumSwitchArms(stripped, 'لا وجودَ لها', 'D'),
        throwsStateError);
    expect(() => _enumSwitchArms('X? get r => switch (k) { D.a => 1,', 'X? get r', 'D'),
        throwsStateError);
  });
}
