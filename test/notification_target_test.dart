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

  // ── (٦) ومسارا الوجهتَين مُعلَنانِ فعلاً ──────────────────────────────
  test('/contracts و/support مسارانِ في router.dart', () {
    final r = _strip(File('lib/router.dart').readAsStringSync());
    for (final path in const ['/contracts', '/support']) {
      expect(r.contains("path: '$path'"), isTrue,
          reason: 'القاعدةُ تُعيدُ $path ولا يَعرفُه go_router — نقرٌ بلا نقل');
    }
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
}
