// حارسُ **«أهذه الرسالةُ منّا أم منها؟»** — قرارٌ واحدٌ بأربعةِ قُرّاءٍ في
// ثلاثِ لغات، وقد افترقَ، وحقلاهُ يَكتبُهما العميل.
//
// ═══ العطلُ المَحروس (2026-10-05) ═══
//
// قاعدةُ `support_tickets/{t}/messages` كانت `allow read, create` بلا قيدٍ
// على **المحتوى**: مالكةُ التذكرةِ تُنشئُ رسالةً بأيِّ حقول. وأربعةُ قُرّاءٍ
// يُقرّرونَ الكاتبَ من `senderRole`/`senderId`:
//
//   • `sendNotificationOnTicketReply` — فرعُ «ردُّ الدعم» يُشعِرُ العميلةَ،
//     وفرعُ «ردُّ العميلة» يُشعِرُ الإدارة. فرسالةٌ تَحملُ `senderRole:
//     'admin'` **تُسقِطُ تنبيهَ «رد جديد على تذكرة دعم» عن مديرِ الطلباتِ
//     كلَّه** وتُرسِلُ إليها «تم الرد على تذكرتك».
//   • `Support.tsx` و`admin_ticket_details_screen` — يَرسمانِ نصَّها في
//     **جهةِ الفريق**، فالخيطُ يُقرأُ عند الأدمنِ كأنّ الفريقَ أجاب.
//
// **مُثبَتٌ على المُحاكي** لا مُستنتَجاً: بالقاعدةِ القديمةِ يَنجحُ إنشاءُ
// رسالةٍ بـ`senderRole:'admin'` و`senderName:'فريق زيارة'` في تذكرتِها.
//
// وافتراقٌ قائمٌ بذاته: القارئُ الرابعُ (`admin_ticket_details_screen`) كان
// `senderRole != 'admin'` **وحدَه** بينما الثلاثةُ تَقرأُ الحقلَين — فمستندٌ
// بـ`senderId:'admin'` بلا `senderRole` يُقرأُ في اللوحةِ والخادمِ «من
// الفريق» وفي تطبيقِ الإدارةِ «منها»: سطحانِ إداريّانِ على وجهَين.
//
// ═══ وما يَنفُذُ متى ═══
//
// **القاعدةُ هي الإصلاحُ الجذريُّ** (لا يُؤمَّنُ سطحٌ يَكتبُه العميلُ من
// جهةِ القارئ)، وهي محجوزةٌ خلفَ STAGE-C. والقاعدةُ المشترَكةُ تُصلِحُ
// الافتراقَ اليومَ وتَعضُّ على الصياغةِ التي يُنتجُها مسارُ التطبيقِ
// (`senderId` = uid نفسِها يَنقضُ الادّعاء) — وصياغةٌ تَحذفُ `senderId`
// تَبقى مقبولةً حتى تَنزلَ القاعدة. يُقالُ كما هو.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/ticket_authorship.dart';

// ── جدولُ الحالاتِ المشترَكُ بين اللغاتِ الثلاث ──
// ملاحظة: الكتلةُ بين العلامتَين تُقرأُ حرفيّاً من فحصَي JS و TS ثمّ
// تُقارَنُ `jsonDecode`اً — فحالةٌ تُضافُ لجهةٍ دون الأخرى تَسقط.
// TICKET_AUTHORSHIP_CASES_BEGIN
const String _casesJson = '''
[
  [{"senderUid": "a9", "senderRole": "admin"}, "u1", "team"],
  [{"senderUid": "a9"}, "u1", "team"],
  [{"senderUid": "u1", "senderRole": "admin"}, "u1", "client"],
  [{"senderUid": "u1"}, "u1", "client"],
  [{"senderRole": "admin", "senderName": "فريق زيارة"}, "u1", "team"],
  [{"senderId": "admin"}, "u1", "team"],
  [{"senderRole": "admin", "senderId": "u1"}, "u1", "client"],
  [{"senderId": "admin", "senderRole": "user"}, "u1", "team"],
  [{"senderId": "u1", "senderRole": "user"}, "u1", "client"],
  [{"senderId": "u1"}, "u1", "client"],
  [{"text": "hi"}, "u1", "client"],
  [{"senderRole": "admin"}, null, "team"],
  [{"senderId": "u1", "senderRole": "admin"}, null, "team"],
  [{"senderUid": "   ", "senderRole": "admin"}, "u1", "team"],
  [{"senderRole": "", "senderId": ""}, "u1", "client"]
]
''';
// TICKET_AUTHORSHIP_CASES_END

String _stripJs(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final List<dynamic> cases = jsonDecode(_casesJson) as List<dynamic>;

  test('جدولُ الحالاتِ قُرِئ فعلاً (لا فحصٌ أجوف)', () {
    expect(cases.length, greaterThanOrEqualTo(12));
  });

  group('القاعدة: الفاعلُ لا الادّعاء', () {
    for (int i = 0; i < cases.length; i++) {
      final row = cases[i] as List<dynamic>;
      final msg = (row[0] as Map).cast<String, dynamic>();
      final owner = row[1] as String?;
      final want = row[2] as String;
      test('حالة ${i + 1}: $msg (مالك=$owner) ⇒ $want', () {
        expect(ticketMessageSender(msg, owner).name, want);
        expect(ticketMessageIsFromTeam(msg, owner), want == 'team');
      });
    }
  });

  test('تلفيقُ «الإدارة» بـuid صاحبةِ التذكرةِ يُقرأُ «منها»', () {
    // هذا هو ما يَعضُّ **اليومَ**: مسارُ التطبيقِ يَكتبُ `senderId` = uid
    // نفسِها، فتلفيقٌ يَحفظُه يُنقَضُ بلا انتظارِ نشرِ القواعد.
    expect(
        ticketMessageSender(
            {'senderRole': 'admin', 'senderName': 'فريق زيارة',
              'senderId': 'u1'},
            'u1'),
        TicketSender.client);
  });

  // ── القُرّاءُ الأربعةُ يُنادونَ القاعدةَ، ولا تعدادَ محلّيّاً باقياً ──
  group('مواضعُ النداء', () {
    final consumers = <String, String>{
      'lib/screens/admin/admin_ticket_details_screen.dart':
          'ticketMessageIsFromTeam(',
      'lib/screens/support_screen.dart': 'ticketMessageIsFromTeam(',
      'admin_panel/src/pages/Support.tsx': 'ticketMessageIsFromTeam(',
      'functions/index.js': 'ticketMessageIsFromTeam(',
    };
    for (final e in consumers.entries) {
      test('${e.key} يُنادي القاعدة', () {
        expect(File(e.key).readAsStringSync().contains(e.value), isTrue,
            reason: 'قارئٌ لا يُنادي القاعدةَ المشترَكة');
      });
    }

    test('ولا نسخةَ إنلاين باقيةً من الادّعاءِ في أيٍّ منها', () {
      // المجموعةُ كاملةً: نسخةٌ ثانيةٌ هي ما افترقَ أصلاً.
      final inline = <String>[];
      for (final f in consumers.keys) {
        final code = _stripJs(File(f).readAsStringSync());
        for (final re in [
          RegExp(r"""senderRole\s*[!=]==?\s*['"]admin['"]"""),
          RegExp(r"""senderId\s*[!=]==?\s*['"]admin['"]"""),
        ]) {
          if (re.hasMatch(code)) inline.add(f);
        }
      }
      expect(inline, isEmpty,
          reason: 'تعدادٌ محلّيٌّ باقٍ في: ${inline.toSet()}');
    });

    test('المضادّة: الشرحُ القديمُ ما زال في الخامّ', () {
      // الفحصُ أعلاه يَقرأُ المُجرَّدَ؛ وهذا يُثبِتُ أنّ التجريدَ لم يُفرِغ
      // الملفَّ من معناه (الفخُّ المسجَّلُ في هذا المستودعِ مرّاتٍ).
      expect(
          File('functions/index.js')
              .readAsStringSync()
              .contains('senderRole === "admin" || senderId === "admin"'),
          isTrue,
          reason: 'شرحُ الفرعِ القديمِ زال، فلا يُعرَفُ لِمَ تغيّرَ القرار');
    });
  });

  // ── الكاتبانِ الإداريّانِ يُسجّلانِ uid الحقيقيَّ ──
  group('الكاتبان', () {
    test('تطبيقُ الإدارةِ يَكتبُ senderUid من Auth', () {
      final s =
          File('lib/screens/admin/admin_ticket_details_screen.dart')
              .readAsStringSync();
      expect(s.contains("'senderUid': FirebaseAuth.instance.currentUser?.uid"),
          isTrue,
          reason: 'بلا uid حقيقيٍّ يَبقى المِعيارُ ادّعاءً — ولا سجلَّ لِمَن أجاب');
    });

    test('ولوحةُ الويبِ كذلك', () {
      final s = File('admin_panel/src/pages/Support.tsx').readAsStringSync();
      expect(s.contains('senderUid: auth.currentUser?.uid'), isTrue);
    });
  });

  // ── القاعدةُ في `firestore.rules` هي الإصلاحُ الجذريّ ──
  group('firestore.rules', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('match /messages/{messageId}');
    final block = i < 0
        ? ''
        : rules.substring(i, rules.indexOf('match /', i + 10) < 0
            ? rules.length
            : rules.indexOf('match /', i + 10));

    test('إنشاءُ العميلةِ مقيَّدٌ بالدورِ وبالمعرّفِ وبمجموعةِ الحقول', () {
      expect(block.isNotEmpty, isTrue, reason: 'كتلةُ messages اختفت');
      expect(block.contains("get('senderRole', 'user') == 'user'"), isTrue,
          reason: 'الادّعاءُ ما زال مقبولاً من العميلة');
      expect(
          block.contains(
              "get('senderId', request.auth.uid)\n              == request.auth.uid") ||
              block.contains("get('senderId', request.auth.uid)"),
          isTrue,
          reason: 'senderId غيرُ مربوطٍ بالمُنشِئ');
      expect(block.contains('hasOnly('), isTrue,
          reason: 'حقلٌ إضافيٌّ (مثل senderUid مُلفَّقاً) ما زال مقبولاً');
      expect(block.contains('allow create: if isAdmin() ||'), isTrue,
          reason: 'الإداريُّ يَجبُ أن يَبقى بلا قيد');
    });

    test('ومجموعةُ الحقولِ المسموحةِ = ما يَكتبُه التطبيقُ فعلاً', () {
      // كـ`amounts.test.js`: حقلٌ جديدٌ في الشاشةِ بلا تعديلِ القاعدةِ
      // يَسقطُ هنا بدلَ أن يُرفَضَ عند العميلة.
      final m = RegExp(r"hasOnly\(\[([^\]]*)\]\)").firstMatch(block);
      expect(m, isNotNull);
      final allowed = RegExp(r"'([a-zA-Z_]+)'")
          .allMatches(m!.group(1)!)
          .map((x) => x.group(1)!)
          .toSet();
      expect(allowed, kClientTicketMessageFields.toSet(),
          reason: 'القاعدةُ والقائمةُ المُعلَنةُ افترقتا');

      // وما تَكتبُه الشاشةُ فعلاً: كلُّ `add({...})` على messages.
      final src = File('lib/screens/support_screen.dart').readAsStringSync();
      final written = <String>{};
      for (final mm
          in RegExp(r"collection\('messages'\)\s*\.?\s*\n?\s*\.add\(\{")
              .allMatches(src)) {
        final open = src.indexOf('{', mm.end - 1);
        int depth = 0, end = -1;
        for (int j = open; j < src.length; j++) {
          if (src[j] == '{') depth++;
          if (src[j] == '}') {
            depth--;
            if (depth == 0) {
              end = j;
              break;
            }
          }
        }
        if (end < 0) continue;
        written.addAll(RegExp(r"'([a-zA-Z_]+)'\s*:")
            .allMatches(src.substring(open, end))
            .map((x) => x.group(1)!));
      }
      expect(written, isNotEmpty, reason: 'لم تُستخرَج كتاباتُ الشاشة');
      expect(written.difference(allowed), isEmpty,
          reason: 'الشاشةُ تَكتبُ حقلاً تَرفضُه القاعدة: '
              '${written.difference(allowed)}');
    });
  });
  // ── وثيقةُ التذكرةِ نفسُها: حقلانِ لا غير (2026-10-07) ──
  //
  // الرسالةُ أُحكِمت أعلاه، **والوثيقةُ الأمُّ بَقيت مفتوحةَ الحقولِ
  // لصاحبتِها**: شرطُ `request.auth.uid == resource.data.userId` يَقرأُ
  // المستندَ القائمَ فمِلكيّتُها اليومَ ثابتةٌ، و`request.resource` (الجديدُ)
  // بلا قيدٍ إطلاقاً. وما تَكتبُه الشاشةُ حقلانِ: `status: 'open'`
  // و`updatedAt` عند إرسالِ ردِّها.
  //
  // فالمفتوحُ بالفارقِ كان `userEmail` — وهو ما يَقرؤه الأدمنُ **هُويّةَ
  // المشتكية** («من: …») ويَبحثُ به في السطحَين — و`userId` (نقلُ التذكرةِ
  // إلى uid آخرَ بعد إنشائها) و`status` (ضبطُه `resolved` يُخرِجُ الشكوى من
  // تبويبِ «النشطة» `['open','replied']`) و`subject`/`lastMessage`.
  // (ولا ترحيلَ بريدٍ خلفَه: صفرُ قراءةٍ لـ`userEmail` في `functions/`
  // — فالأثرُ تضليلُ الدعمِ لا إرسالٌ من نطاقِنا؛ وفحصٌ أدناه يُبقي ذلك
  // التعليلَ مقروءاً.)
  group('firestore.rules — وثيقةُ التذكرة', () {
    final rules = File('firestore.rules').readAsStringSync();
    final int i = rules.indexOf('match /support_tickets/{ticketId}');
    final int j = rules.indexOf('match /messages/{messageId}', i);
    final String block = (i < 0 || j < 0) ? '' : rules.substring(i, j);

    test('تحديثُ العميلةِ مقيَّدٌ بمجموعةِ الحقولِ وبقيمةِ الحالة', () {
      expect(block.isNotEmpty, isTrue,
          reason: 'كتلةُ support_tickets اختفت أو انقلبَ ترتيبُها');
      expect(block.contains('allow update: if isAdmin() ||'), isTrue,
          reason: 'الإداريُّ يَجبُ أن يَبقى بلا قيد');
      expect(block.contains('affectedKeys()'), isTrue,
          reason: 'التحديثُ بلا تقييدِ حقول — `userEmail` و`userId` مفتوحان');
      expect(block.contains("request.resource.data.status == 'open'"), isTrue,
          reason: 'العميلةُ تَستطيعُ إخراجَ شكواها من تبويبِ النشطة');
      // والقراءةُ فُصِلت عن التحديث: `allow read, update` واحدةً كانت تَعني
      // أنّ تقييدَ الحقولِ يُقيّدُ القراءةَ أيضاً.
      expect(block.contains('allow read: if isLoggedIn()'), isTrue,
          reason: 'قراءةُ صاحبةِ التذكرةِ انكسرت مع التقييد');
    });

    test('ومجموعةُ الحقولِ المسموحةِ = ما تَكتبُه الشاشةُ فعلاً', () {
      // شكلُ حادثةِ `invoice_pdf_status`: حقلٌ جديدٌ في الشاشةِ بلا تعديلِ
      // القاعدةِ يُرفَضُ **التحديثُ كلُّه** — فيَسقطُ هنا لا عند العميلة.
      final m = RegExp(r"hasOnly\(\[([^\]]*)\]\)").firstMatch(block);
      expect(m, isNotNull, reason: 'لا hasOnly في كتلةِ الوثيقة');
      final allowed = RegExp(r"'([a-zA-Z_]+)'")
          .allMatches(m!.group(1)!)
          .map((x) => x.group(1)!)
          .toSet();

      final src = File('lib/screens/support_screen.dart').readAsStringSync();
      final written = <String>{};
      int scanned = 0;
      for (final mm in RegExp(
              r"collection\('support_tickets'\)[\s\S]{0,120}?\.update\(\{")
          .allMatches(src)) {
        final open = src.indexOf('{', mm.end - 1);
        int depth = 0, end = -1;
        for (int k = open; k < src.length; k++) {
          if (src[k] == '{') depth++;
          if (src[k] == '}') {
            depth--;
            if (depth == 0) {
              end = k;
              break;
            }
          }
        }
        if (end < 0) continue;
        scanned++;
        written.addAll(RegExp(r"'([a-zA-Z_]+)'\s*:")
            .allMatches(src.substring(open, end))
            .map((x) => x.group(1)!));
      }
      expect(scanned, greaterThan(0),
          reason: 'لم تُستخرَج أيُّ كتابةٍ على الوثيقة — فحصٌ أجوف');
      expect(written.difference(allowed), isEmpty,
          reason: 'الشاشةُ تَكتبُ حقلاً تَرفضُه القاعدةُ فيُرفَضُ التحديثُ '
              'كلُّه: ${written.difference(allowed)}');
      expect(allowed.difference(written), isEmpty,
          reason: 'القاعدةُ تُجيزُ حقلاً لا تَكتبُه الشاشة: '
              '${allowed.difference(written)}');
    });

    test('والتعليلُ مأخوذٌ من الشفرة: `userEmail` هُويّةٌ تُقرَأُ ولا تُرسَلُ', () {
      // (أ) الأدمنُ يَقرؤه هُويّةَ المشتكية في السطحَين.
      final panel =
          File('admin_panel/src/pages/Support.tsx').readAsStringSync();
      final appAdmin =
          File('lib/screens/admin/admin_support_screen.dart').readAsStringSync();
      expect(panel.contains('userEmail'), isTrue,
          reason: 'اللوحةُ لم تَعُدْ تَقرأُ userEmail — يُراجَعُ التعليل');
      expect(appAdmin.contains("'userEmail'"), isTrue,
          reason: 'شاشةُ الإدارةِ لم تَعُدْ تَقرأُ userEmail');
      // (ب) ولا يُرسَلُ إليه بريد — فالأثرُ تضليلٌ لا ترحيل. لو صارَ مُرسَلاً
      //     إليه فالخطرُ يَرتفعُ ويُراجَعُ هذا المدخلُ لا يُسكَت.
      final fns = File('functions/index.js').readAsStringSync();
      expect(fns.contains('userEmail'), isFalse,
          reason: 'الخادمُ صارَ يَقرأُ userEmail — إن كان وجهةَ بريدٍ '
              'فالثغرةُ ترحيلُ بريدٍ لا تضليلاً، فيُراجَعُ التعليلُ والقاعدة');
      // (ج) وتبويبُ «النشطة» ما زال يُقصي `resolved` — وهو سببُ تثبيتِ القيمة.
      expect(appAdmin.contains("['open', 'replied']"), isTrue,
          reason: 'تبويبُ النشطةِ تغيّر — يُراجَعُ تثبيتُ `status == open`');
    });
  });
}
