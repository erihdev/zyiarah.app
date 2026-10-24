// قوائمُ الإدارةِ المقصوصةُ لا تَقولُ «لا نتائج» ولا «إجمالي» عن نافذة —
// وشاشةُ الطلباتِ لا تَرسمُ شريطاً ثانياً حين تكونُ تبويباً (2026-10-11).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/strip_comments.dart';

String _code(String p) => stripComments(File(p).readAsStringSync());

void main() {
  group('بحثُ العملاءِ يَصلُ إلى كلِّ العملاء لا إلى أحدثِ مئة', () {
    final src = _code('lib/screens/admin/admin_users_screen.dart');

    test('بحثٌ خادميٌّ بالبادئةِ على الاسمِ والبريدِ والجوّال', () {
      expect(src, contains("_byPrefix('name'"));
      expect(src, contains("_byPrefix('email'"));
      expect(src, contains("_byPrefix('phone'"));
      expect(src, contains('isGreaterThanOrEqualTo: prefix'));
      expect(src, contains("isLessThan: '\$prefix\\uf8ff'"));
    });

    test('بلا فهرسٍ مركَّبٍ جديد: لا `role ==` مع مدى البادئة', () {
      final j = src.indexOf('Future<QuerySnapshot<Map<String, dynamic>>> _byPrefix');
      final body = src.substring(j, src.indexOf(';', j));
      expect(body, isNot(contains("'role'")),
          reason: 'role مع مدًى على حقلٍ آخر يَستلزمُ فهرساً مركَّباً');
      // `role` يُرشَّحُ محلّيّاً بعدَ الجلب.
      expect(src, contains("d.data()['role'] == 'client'"));
      // ولا فهرسَ مركَّباً على users فيه name/email/phone.
      final idx = jsonDecode(File('firestore.indexes.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final ix in (idx['indexes'] as List).cast<Map<String, dynamic>>()) {
        if (ix['collectionGroup'] != 'users') continue;
        final fields = (ix['fields'] as List)
            .map((f) => (f as Map)['fieldPath'])
            .toSet();
        expect(fields.intersection({'name', 'email', 'phone'}), isEmpty);
      }
    });

    test('القراءةُ بمهلة، والنافذةُ المقصوصةُ تُقال', () {
      final j = src.indexOf('Future<QuerySnapshot<Map<String, dynamic>>> _byPrefix');
      expect(src.substring(j, src.indexOf(';', j)),
          contains('.timeout(kNetCallTimeout)'));
      expect(src, contains('المعروض أحدث \$_windowLimit عميل'));
      expect(src, contains('.limit(_windowLimit)'));
      expect(src, isNot(contains('.limit(100)')),
          reason: 'السقفُ مكتوبٌ مرّتَين فتَنفصلُ ملاحظتُه عنه');
    });
  });

  group('سجلُّ الفواتير: لا قصَّ صامتاً عند سقفِ الألف', () {
    final src = _code('lib/screens/admin/admin_invoices_screen.dart');
    test('السقفُ ثابتٌ واحدٌ وبلوغُه يُرفَعُ علَماً', () {
      expect(src, contains('static const int _queryLimit = 1000;'));
      expect(src, contains('.limit(_queryLimit)'));
      expect(src, isNot(contains('.limit(1000)')));
      expect(src, contains('if (snap.docs.length >= _queryLimit) capped.add(source);'));
    });
    test('الملاحظةُ تُرسَمُ قبلَ الملخّص', () {
      final notice = src.indexOf('_cappedNotice(),');
      final summary = src.indexOf('_summaryCard(summary),');
      expect(notice, greaterThan(0));
      expect(notice, lessThan(summary),
          reason: 'رقمٌ يُقرأُ أوّلاً، فتقييدُه بعدَه لا يَمنعُ قراءتَه دعوى');
    });
  });

  test('شاشةُ الطلباتِ تبويباً: `embedded` يُسقطُ الشريطَ الخاصّ، والافتراضُ الحاليّ', () {
    final src = _code('lib/screens/admin/admin_orders_screen.dart');
    expect(src, contains('this.embedded = false'));
    expect(src, contains('appBar: widget.embedded'));
  });
}
