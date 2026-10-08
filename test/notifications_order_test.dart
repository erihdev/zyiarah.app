// حارس: **صندوقُ إشعاراتِ العميلةِ كان يُعرَضُ بترتيبِ المعرّفِ لا بالأحدث.**
//
// `limit()` بلا `orderBy` لا يُعيدُ «أحدثَ N»: يُعيدُ N بترتيبِ `__name__`،
// ومعرّفاتُ `notifications` من `.add()` أي عشوائيّةٌ تماماً. فثلاثةُ
// استعلاماتٍ عميليّةٍ كانت تُنتجُ مجموعةً **كيفما اتّفقت**:
//
//   • بثُّ قائمةِ «الإشعارات» (`_firestoreBody`) — فالصفحةُ الأولى ليست
//     أحدثَ الإشعاراتِ، وإشعارٌ جديدٌ قد لا يَظهرَ أصلاً بعد تجاوزِ
//     العتبة. والفرزُ المحلّيُّ هناك يُرتّبُ **داخلَ** الصفحةِ فحسب.
//   • ترقيمُ الصفحاتِ (`_loadMore`) — ومؤشّرُ `startAfterDocument` لا
//     معنى له إلّا في ترتيبٍ مُعلَن.
//   • نقطةُ الجرسِ في اللوحةِ الرئيسيّة — فتَظهرُ عن إشعارٍ قديمٍ غيرِ
//     مقروءٍ وتَغيبُ عن أحدثِ إشعارٍ وصل.
//
// **وشاشةُ السائقِ أُصلحت بهذا بعينِه** وتعليقُها يَحكيه («بلا orderBy كان
// limit(50) يُرجع أقدم 50 مستنداً بترتيب المعرّف (لا الأحدث)، فتختفي
// إشعارات الإسناد الجديدة بعد تجاوز 50») — فالقاعدةُ كانت مُنفَّذةً في
// سطحٍ من ثلاثة. والفهرسُ `(userId, sentAt DESC)` قائمٌ أصلاً لأجلِها،
// فالإصلاحُ بلا فهرسٍ جديد.
//
// **وشرطُ صحّةِ الإصلاح**: `orderBy` يُسقِطُ المستندَ الذي لا يَحملُ حقلَ
// الترتيب. فيَلزمُ أن يَكتبَ **كلُّ** كاتبٍ للمجموعةِ `sentAt` — وذاك ما
// يَشدُّه الفحصُ (ج)، وهو التعليلُ لا تزييناً.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

void main() {
  final String idx = File('functions/index.js').readAsStringSync();

  /// سلسلةُ استعلامٍ تَبدأُ عند `.collection('notifications')` وتَنتهي عند
  /// `;` على عمقِ صفر — بموازنةِ الأقواسِ لا بنافذةِ عدِّ أحرف.
  List<String> chainsIn(String code) {
    final List<String> out = [];
    for (final m
        in RegExp(r"\.collection\(\s*'notifications'\s*\)").allMatches(code)) {
      int depth = 0;
      int end = code.length;
      for (int i = m.end; i < code.length; i++) {
        final String c = code[i];
        if (c == '(' || c == '[' || c == '{') {
          depth++;
        } else if (c == ')' || c == ']' || c == '}') {
          depth--;
        } else if ((c == ';' || c == ',') && depth <= 0) {
          // **ونهايةُ السلسلةِ فاصلةٌ أيضاً، لا `;` وحدَها**: بثُّ
          // `StreamBuilder` وسيطٌ مُسمّىً فيَنتهي بفاصلةٍ على عمقِ صفر.
          // وبـ`;` وحدَها كانت السلسلةُ تَبتلعُ **جسمَ البانِي كلَّه** —
          // وفيه كتابةٌ بالمعرّفِ (`.doc(…).update`)، فيُرشَّحُ الاستعلامُ
          // الحقيقيُّ خارجاً: فخُّ الحدِّ بوجهٍ جديد.
          end = i;
          break;
        }
      }
      out.add(code.substring(m.end, end));
    }
    return out;
  }

  group('صندوقُ الإشعاراتِ مُرتَّبٌ بالأحدثِ — نطاقٌ مُشتَقٌّ لا قائمةٌ مكتوبة',
      () {
    final Map<String, List<String>> queries = {};
    for (final f in sourcesIn('lib', atLeast: 100)) {
      final String code = stripComments(f.readAsStringSync());
      final List<String> cs = chainsIn(code)
          // الكتابةُ بالمعرّفِ ليست استعلاماً (تعليمُ الإشعارِ مقروءاً).
          .where((c) => !c.contains('.doc('))
          .toList();
      if (cs.isNotEmpty) queries[f.path.replaceAll(r'\', '/')] = cs;
    }

    test('(أ) الاشتقاقُ أصابَ — حارسٌ عقيمٌ أسوأُ من لا حارس', () {
      final int total =
          queries.values.fold(0, (a, b) => a + b.length);
      expect(total, greaterThanOrEqualTo(4),
          reason: 'كاشفُ السلاسلِ انحلّ ($total سلسلة)');
      expect(queries.keys,
          contains('lib/screens/driver_notifications_screen.dart'));
      expect(queries.keys,
          contains('lib/screens/client_notifications_screen.dart'));
      expect(queries.keys, contains('lib/screens/client_dashboard.dart'));
    });

    test('(ب) كلُّ استعلامٍ يُرتّبُ بـ`sentAt` تنازليّاً', () {
      final List<String> unordered = [];
      queries.forEach((p, cs) {
        for (int i = 0; i < cs.length; i++) {
          if (!cs[i].contains("orderBy('sentAt', descending: true)")) {
            unordered.add('$p#${i + 1}');
          }
        }
      });
      expect(unordered, isEmpty,
          reason: 'استعلامُ إشعاراتٍ بلا ترتيب: النافذةُ تُقرأُ «أحدثَ N» '
              'وهي N بترتيبِ المعرّفِ العشوائيّ: ${unordered.join(", ")}');
    });

    test('(ج) والتعليل: كلُّ كاتبٍ خادميٍّ يَكتبُ `sentAt`', () {
      // `orderBy` يُسقِطُ ما لا يَحملُ الحقل — فهذا شرطُ صحّةِ (ب) لا زينة.
      final String code = stripComments(idx);
      final List<String> missing = [];
      int seen = 0;
      for (final m
          in RegExp(r'collection\("notifications"\)').allMatches(code)) {
        // **المِرساةُ `.set(`/`.add(` لا «أوّلُ `{`»**: المسارُ الوحيدُ ذو
        // المعرّفِ الحتميِّ يَكتبُ ``.doc(`trig_${…}`).set({`` — فأوّلُ `{`
        // بعدَ المجموعةِ هو قوسُ الاستقراءِ داخلَ القالبِ لا حِمْلُ الكتابة،
        // وهو فخُّ الحدِّ المسجَّلُ في هذا المستودعِ مراراً.
        final RegExpMatch? w =
            RegExp(r'\.(?:set|add)\(').firstMatch(code.substring(m.end));
        if (w == null) continue;
        final int brace = code.indexOf('{', m.end + w.end - 1);
        if (brace < 0) continue;
        int depth = 0;
        int end = code.length;
        for (int i = brace; i < code.length; i++) {
          if (code[i] == '{') depth++;
          if (code[i] == '}') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        final String payload = code.substring(brace, end);
        if (!payload.contains('userId')) continue; // ليس حِمْلَ إنشاء
        seen++;
        if (!payload.contains('sentAt')) {
          missing.add('index.js:'
              '${code.substring(0, m.start).split('\n').length}');
        }
      }
      expect(seen, greaterThanOrEqualTo(5),
          reason: 'كاشفُ الكُتّابِ الخادميّينَ انحلّ ($seen)');
      expect(missing, isEmpty,
          reason: 'كاتبٌ لا يَكتبُ `sentAt` — فـ`orderBy` يُسقِطُ مستندَه '
              'من صندوقِ الإشعاراتِ كلِّه: ${missing.join(", ")}');
    });

    test('(د) ولا كاتبَ عميليٍّ يُنشئُ إشعاراً', () {
      // عميلٌ يُنشئُ مستنداً بلا `sentAt` يُخفيه الترتيبُ — فالقاعدةُ تَبقى
      // صحيحةً ما بقي الإنشاءُ خادميّاً وحدَه.
      final List<String> creators = [];
      for (final f in sourcesIn('lib', atLeast: 100)) {
        final String code = stripComments(f.readAsStringSync());
        for (final c in chainsIn(code)) {
          if (RegExp(r'\.add\(|\.set\(').hasMatch(c)) {
            creators.add(f.path.replaceAll(r'\', '/'));
          }
        }
      }
      expect(creators, isEmpty,
          reason: 'العميلُ يُنشئُ إشعاراً — فقد يَغيبُ `sentAt` ويُسقِطُه '
              'الترتيب: ${creators.join(", ")}');
    });

    test('(هـ) والفهرسُ قائمٌ — ولا فهرسَ جديداً لهذا الإصلاح', () {
      // يُحلَّلُ JSONاً لا بنمطٍ على النصِّ: نافذةُ عدِّ أحرفٍ بين حقلَين
      // هي فخُّ الحدِّ نفسُه.
      final Map<String, dynamic> cfg = jsonDecode(
          File('firestore.indexes.json').readAsStringSync())
              as Map<String, dynamic>;
      final List<dynamic> idxs = cfg['indexes'] as List<dynamic>;
      final bool has = idxs.any((dynamic raw) {
        final Map<String, dynamic> i = raw as Map<String, dynamic>;
        if (i['collectionGroup'] != 'notifications') return false;
        final List<dynamic> f = i['fields'] as List<dynamic>;
        if (f.length != 2) return false;
        final Map<String, dynamic> a = f[0] as Map<String, dynamic>;
        final Map<String, dynamic> b = f[1] as Map<String, dynamic>;
        return a['fieldPath'] == 'userId' &&
            a['order'] == 'ASCENDING' &&
            b['fieldPath'] == 'sentAt' &&
            b['order'] == 'DESCENDING';
      });
      expect(has, isTrue,
          reason: 'الفهرسُ (userId ASC, sentAt DESC) غائبٌ — وهو ما يُجيزُ '
              'الترتيبَ بلا كلفةٍ جديدة');
    });

    test('(و) والترشيحُ يَبقى محلّيّاً: غيابُ `isRead` يُقرأُ «غيرَ مقروء»',
        () {
      // قرارٌ قائم: مساواةُ Firestore تَستلزمُ وجودَ الحقل، و**اثنانِ من
      // الكُتّابِ الخمسةِ لا يَكتبانِ `isRead` إطلاقاً** — فاستعلامُه كان
      // سيُخفي إشعاراتِهما تماماً. فلا استعلامَ عليه في `lib/` كلِّها،
      // والغيابُ يُقرأُ «غيرَ مقروء» في النموذجِ وفي القارئَين الخامَّين.
      for (final f in sourcesIn('lib', atLeast: 100)) {
        final String code = stripComments(f.readAsStringSync());
        expect(code.contains("where('isRead'"), isFalse,
            reason: '${f.path} يَستعلمُ `isRead` — فإشعاراتُ الكاتبَين '
                'اللذَين لا يَكتبانِه تَختفي');
      }
      // النموذجُ: الغيابُ ⇒ `false` (غيرُ مقروء).
      expect(
          stripComments(File('lib/models/notification_item.dart')
                  .readAsStringSync())
              .contains("m['isRead'] == true || m['is_read'] == true"),
          isTrue,
          reason: 'النموذجُ لم يَعُدْ يَقرأُ الغيابَ «غيرَ مقروء»');
      // والقارئانِ الخامّانِ (الجرسُ وشاشةُ السائق).
      for (final p in const [
        'lib/screens/client_dashboard.dart',
        'lib/screens/driver_notifications_screen.dart',
      ]) {
        expect(
            stripComments(File(p).readAsStringSync())
                .contains("['isRead'] != true"),
            isTrue,
            reason: '$p لم يَعُدْ يُرشّحُ محلّيّاً');
      }
    });
  });
}
