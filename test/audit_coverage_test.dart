// سجلُّ العمليّاتِ الإداريّةِ — تسميةٌ لكلِّ إجراءٍ، وأثرٌ لكلِّ كتابة.
//
// ترويسةُ الشاشةِ تَقولُ «هذا السجل يوثق **كافة** التغييرات الجوهرية التي
// يقوم بها أعضاء الفريق الإداري» — وكانت كاذبةً في الاتجاهَين:
//
//   • **٣٢ اسماً من ٤٩** يُكتَبُ ولا تسميةَ له، فيُعرَضُ بحرفِه اللاتينيِّ
//     عنواناً لبطاقةٍ في واجهةٍ عربيّة: «BAN_USER»، «DELETE_PRODUCT»،
//     «REVIEW_ORDER_PRICE». والسببُ أنّ الخريطةَ كانت `switch` **تعداداً**
//     بفرعٍ جامعٍ `default: return action;` داخلَ شاشةِ العرض، فكلُّ إجراءٍ
//     أُضيفَ بعدَها سقطَ منها بصمت — شكلُ `order_activity` بعينِه.
//   • **أربعُ شاشاتٍ إداريّةٍ تَكتبُ بلا أثر**، وثلاثٌ منها كتابةٌ **مطابقةٌ**
//     لكتابةٍ مُقيَّدةٍ في شاشةٍ أخرى: تعطيلُ سائقٍ من شاشةِ الامتثال
//     (مُقيَّدٌ في شاشةِ الكوادر)، وبثُّ الامتثالِ (مُقيَّدٌ في شاشةِ البث)،
//     وتنفيذُ حذفِ حساب (طلبُه مُقيَّدٌ في شاشةِ المستخدمين) — ومعها اعتمادُ
//     العقدِ وحذفُه، و«APPROVE_CONTRACT» تسميةٌ كانت في الشاشةِ بلا كاتب.
//   • و`AUDIT.UPDATE_SETTINGS` **مُعلَنٌ في لوحةِ الويبِ بلا مُنادٍ واحد** —
//     الاسمُ وُجدَ لحفظِ الإعداداتِ (وضعُ الصيانةِ، بوّابةُ الإصدار، سياسةُ
//     الخصوصيّةِ المنشورةُ) ولم يُستعمَلْ في أيِّ جهة.
//
// فالنطاقُ **مُشتَقٌّ**: مجموعةُ ما يُكتَبُ تُقرأُ من المستودعِ كلِّه ويُقابَلُ
// بمجموعةِ التسمياتِ **كاملةً في الاتجاهَين**، فاسمٌ جديدٌ يَسقطُ الفحصَ يومَ
// كتابتِه لا يومَ قراءتِه، وتسميةٌ لإجراءٍ زالَ تُراجَعُ بدلَ أن تَتعفّن.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/audit_actions.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// نهايةُ القوسِ المُوازِنِ لقوسٍ يَبدأُ عندَ [i].
int _bal(String s, int i, [String open = '(', String close = ')']) {
  var d = 0;
  for (var k = i; k < s.length; k++) {
    if (s[k] == open) {
      d++;
    } else if (s[k] == close) {
      d--;
      if (d == 0) return k;
    }
  }
  return -1;
}

/// الوسيطُ الأوّلُ بعدَ `action:` حتى فاصلةٍ على العمقِ صفر.
String _actionArg(String body) {
  final m = RegExp(r'action:\s*').firstMatch(body);
  if (m == null) return '';
  final buf = StringBuffer();
  var d = 0;
  for (var k = m.end; k < body.length; k++) {
    final ch = body[k];
    if ('([{'.contains(ch)) {
      d++;
    } else if (')]}'.contains(ch)) {
      d--;
    } else if (ch == ',' && d == 0) {
      break;
    }
    buf.write(ch);
  }
  return buf.toString();
}

void main() {
  final svcRaw = File('lib/services/audit_service.dart').readAsStringSync();
  final constToValue = <String, String>{
    for (final m in RegExp(r"static const String (action\w+)\s*=\s*'([^']+)'")
        .allMatches(svcRaw))
      m.group(1)!: m.group(2)!,
  };

  /// كلُّ اسمِ إجراءٍ يُكتَبُ في المستودع ← الملفّاتُ التي تَكتبُه.
  final written = <String, Set<String>>{};
  void add(String a, String f) =>
      written.putIfAbsent(a, () => <String>{}).add(f);

  // (١) دارت: `action:` داخلَ نداءِ `logAction(` مُوازَنٍ — لا أيُّ `action:`
  // في الملفِّ: `_queueNotification(action: …)` في خدمةِ المراسلةِ يَكتبُ
  // `notification_triggers` لا `audit_logs`، وكان يُقرأُ قيداً زوراً.
  for (final f in sourcesIn('lib', atLeast: 100)) {
    if (f.path.endsWith('audit_service.dart') ||
        f.path.endsWith('admin_audit_logs_screen.dart') ||
        f.path.endsWith('audit_actions.dart')) {
      continue;
    }
    final code = stripComments(f.readAsStringSync());
    for (final m in RegExp(r'logAction\s*\(').allMatches(code)) {
      // `expect` غيرُ مشروعٍ في نطاقِ `main` (OutsideTestException) — فالفشلُ
      // هنا يُرمى، والفحوصُ أدناه تَقرأُ الناتج.
      final end = _bal(code, m.end - 1);
      if (end < 0) {
        throw StateError('نداءُ logAction غيرُ مُوازَنٍ في ${f.path}');
      }
      final arg = _actionArg(code.substring(m.end, end));
      final names = <String>[
        ...RegExp(r"'([A-Z_]+)'").allMatches(arg).map((x) => x.group(1)!),
        ...RegExp(r'ZyiarahAuditService\.(action\w+)')
            .allMatches(arg)
            .map((x) => constToValue[x.group(1)!]!),
      ];
      if (names.isEmpty) {
        throw StateError('اسمُ الإجراءِ لم يُحَلَّ في ${f.path}: $arg');
      }
      for (final n in names) {
        add(n, f.uri.pathSegments.last);
      }
    }
  }

  // (٢) اللوحة: `logAudit(AUDIT.X`.
  for (final f in sourcesIn('admin_panel/src',
      atLeast: 20, exts: const ['.ts', '.tsx'])) {
    if (f.path.endsWith('services/audit.ts')) continue;
    for (final m in RegExp(r'logAudit\(\s*AUDIT\.([A-Z_]+)')
        .allMatches(f.readAsStringSync())) {
      add(m.group(1)!, f.uri.pathSegments.last);
    }
  }

  // (٣) الخادم: `action` داخلَ `collection("audit_logs").add({…})`.
  final idx = File('functions/index.js').readAsStringSync();
  for (final m in RegExp(r'collection\("audit_logs"\)\s*\.\s*add\s*\(')
      .allMatches(idx)) {
    final body = idx.substring(m.end, _bal(idx, m.end - 1));
    final a = RegExp(r'action:\s*"([A-Z_]+)"').firstMatch(body);
    if (a != null) add(a.group(1)!, 'index.js');
  }

  group('سجلُّ التدقيق: تسميةٌ لكلِّ إجراءٍ يُكتَب', () {
    test('(أ) الاشتقاقُ أصابَ: أسماءٌ من الجهاتِ الثلاث', () {
      // بلا أرضيّةٍ يَصيرُ كلُّ ما تَحتَه أخضرَ أجوفَ متى انحلَّ المُستخرِج.
      expect(written.length, greaterThanOrEqualTo(40),
          reason: 'استخراجُ أسماءِ الإجراءاتِ انحلَّ — الفحصُ أدناه عقيم');
      expect(written['DELETE_STAFF'], contains('index.js'),
          reason: 'لم يُقرأِ الكاتبُ الخادميّ');
      expect(
          written['REVIEW_ORDER_PRICE'],
          containsAll(
              <String>['Orders.tsx', 'admin_order_details_screen.dart']),
          reason: 'لم يُقرأْ كاتبُ اللوحةِ أو كاتبُ التطبيق');
    });

    test('(ب) كلُّ اسمٍ يُكتَبُ له تسميةٌ عربيّة', () {
      final raw = written.keys
          .where((a) => !kAuditActionLabels.containsKey(a))
          .toList()
        ..sort();
      expect(raw, isEmpty,
          reason: 'تُعرَضُ بحرفِها اللاتينيِّ في سجلٍّ عربيّ: $raw');
    });

    test('(ج) ولا تسميةً لإجراءٍ لا يُكتَبُ ولا سببَ له', () {
      // المجموعةُ كاملةً في الاتجاهِ الآخر: مفتاحٌ بلا كاتبٍ يَجبُ أن يكونَ
      // مُعلَناً في `kAuditActionsWithoutWriter` بسببِه — فلا تَتعفّنُ الخريطةُ
      // بتسمياتٍ لإجراءاتٍ زالت.
      final orphan = kAuditActionLabels.keys
          .where((a) =>
              !written.containsKey(a) &&
              !kAuditActionsWithoutWriter.contains(a))
          .toList()
        ..sort();
      expect(orphan, isEmpty, reason: 'تسميةٌ بلا كاتبٍ وبلا سبب: $orphan');
    });

    test('(د) والمُعلَنُ «بلا كاتب» بلا كاتبٍ فعلاً', () {
      final live = kAuditActionsWithoutWriter
          .where(written.containsKey)
          .toList()
        ..sort();
      expect(live, isEmpty,
          reason: 'صارَ له كاتبٌ — يُرفَعُ من القائمةِ لا يُسكَت: $live');
      // ومُعلَنٌ لا تسميةَ له لا معنى له.
      for (final a in kAuditActionsWithoutWriter) {
        expect(kAuditActionLabels.containsKey(a), isTrue,
            reason: '$a بلا تسمية');
      }
    });

    test('(هـ) الشاشةُ تُنادي القاعدةَ ولا تَعُدُّ التسمياتِ بنفسِها', () {
      final v = File('lib/screens/admin/admin_audit_logs_screen.dart')
          .readAsStringSync();
      expect(RegExp(r'auditActionLabel\s*\(').hasMatch(v), isTrue,
          reason: 'الشاشةُ لا تُنادي القاعدة');
      expect(v.contains('_getActionLabel'), isFalse,
          reason: 'التعدادُ المحلّيُّ عادَ — وهو ما أسقطَ ٣٢ اسماً بصمت');
      expect(stripComments(v).contains("case 'CREATE_STAFF'"), isFalse,
          reason: 'نسخةٌ إنلاين من الخريطةِ عادت');
    });

    test('(و) المضادّة: شرحُ العطلِ ما زال في الخامّ', () {
      // (هـ) تَفحصُ غياباً، فيَلزمُ إثباتُ أنّ المحذوفَ شفرةٌ وأنّ سببَ حذفِها
      // مكتوبٌ — وإلّا لم يَعرفْ قارئٌ ما يَحرُسُه هذا.
      // التسويةُ لازمةٌ: الاقتباسُ يَلتفُّ على سطرَين في تعليقِ الوحدةِ
      // (`/// ` في البداية)، فـ`contains` على الخامِّ يَفشلُ على نصٍّ حاضر.
      final reg = File('lib/utils/audit_actions.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s*///\s*'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(reg.contains('default: return action;'), isTrue,
          reason: 'الصيغةُ القديمةُ لم تَعُدْ مُقتَبَسةً في شرحِ القاعدة');
      expect(reg.contains('_getActionLabel'), isTrue,
          reason: 'اسمُ الدالّةِ المحذوفةِ زال — فلا يَعرفُ قارئٌ ما حُذِف');
      expect(reg.contains('BAN_USER'), isTrue);
    });

    test('(ز) اللوحةُ لا تُعلِنُ إجراءً بلا مُنادٍ', () {
      // `UPDATE_SETTINGS` كان مُعلَناً هناك ولا يُنادِيه شيءٌ — اسمٌ وُجدَ
      // لكتابةٍ بعينِها ولم يُستعمَل، وهي عائلةُ «ادّعاءٌ بلا قارئ».
      final au = File('admin_panel/src/services/audit.ts').readAsStringSync();
      final declared = RegExp(r"^\s{4}([A-Z_]+):\s*'", multiLine: true)
          .allMatches(au)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared.length, greaterThanOrEqualTo(8),
          reason: 'استخراجُ ثوابتِ اللوحةِ انحلّ');
      final unused = declared.difference(written.keys.toSet()).toList()..sort();
      expect(unused, isEmpty, reason: 'مُعلَنٌ بلا مُنادٍ في اللوحة: $unused');
    });
  });

  group('كلُّ كتابةٍ إداريّةٍ لها أثرٌ', () {
    // سلسلةٌ تَبدأُ عندَ `.collection('x')` وتَنتهي عندَ كتابةٍ، بروابطِ
    // السلسلةِ وحدَها بينهما — فلا يُقرأُ `List.add(` كتابةً على Firestore.
    final chain = RegExp(
      r"\.collection\(\s*'([a-z_]+)'\s*\)"
      r"(?:\s*\.\s*(?:doc|where|orderBy|limit)\s*\([^;]*?\))*?"
      r'\s*\.\s*(?:set|update|add|delete)\s*\(',
      dotAll: true,
    );

    final writes = <String, Set<String>>{}; // screen -> collections
    final audits = <String>{};
    for (final f in sourcesIn('lib/screens/admin', atLeast: 20)) {
      final code = stripComments(f.readAsStringSync());
      final name = f.uri.pathSegments.last;
      final cols = chain.allMatches(code).map((m) => m.group(1)!).toSet();
      if (cols.isNotEmpty) writes[name] = cols;
      if (code.contains('logAction')) audits.add(name);
    }

    test('(ح) الاشتقاقُ أصابَ: شاشاتٌ تَكتبُ وشاشاتٌ تُقيّد', () {
      expect(writes.length, greaterThanOrEqualTo(12),
          reason: 'كاشفُ الكتاباتِ انحلّ');
      expect(audits.length, greaterThanOrEqualTo(10),
          reason: 'كاشفُ القيودِ انحلّ');
      expect(writes['admin_compliance_screen.dart'], contains('drivers'));
    });

    test('(ط) شاشةٌ تَكتبُ مجموعةً تُقيّدُها شاشةٌ أخرى تُقيّدُها كذلك', () {
      // جوهرُ الانحراف: نفسُ الكتابةِ، مُقيَّدةً من سطحٍ ومسكوتاً عنها من آخر.
      final drift = <String>[];
      final byCollection = <String, Set<String>>{};
      writes.forEach((screen, cols) {
        for (final c in cols) {
          byCollection.putIfAbsent(c, () => <String>{}).add(screen);
        }
      });
      byCollection.forEach((col, screens) {
        final audited = screens.where(audits.contains);
        final silent = screens.where((s) => !audits.contains(s));
        if (audited.isNotEmpty && silent.isNotEmpty) {
          drift.add('$col: مُقيَّدٌ في $audited وصامتٌ في $silent');
        }
      });
      expect(drift, isEmpty, reason: drift.join(' | '));
    });

    test('(ي) ومجموعةُ الشاشاتِ الصامتةِ كاملةً = المُعلَنةُ بأسبابِها', () {
      // شاشةُ تفاصيلِ التذكرةِ وحدَها: الردُّ **موقَّعٌ في الخيطِ نفسِه**
      // (`senderUid` من Auth بقرارِ تأليفِ التذاكر)، فـ«من أجاب؟» مُجاب؛
      // وقلبُ الحالةِ إلى «مُغلَقة» رجوعٌ عنه ممكنٌ وظاهرٌ في القائمة. فهو
      // مُسجَّلٌ لا مُغيَّر — ولو صارَ الردُّ غيرَ موقَّعٍ يُراجَعُ هذا.
      const allowed = {'admin_ticket_details_screen.dart'};
      final silent = writes.keys.where((s) => !audits.contains(s)).toSet();
      expect(silent, allowed,
          reason: 'شاشةٌ تَكتبُ بلا أثرٍ ولا سببٍ مُعلَن: '
              '${silent.difference(allowed)}');
      // وشاهدُ التعليلِ: الردُّ ما زال يُوقَّعُ من Auth.
      final t = File('lib/screens/admin/admin_ticket_details_screen.dart')
          .readAsStringSync();
      expect(t.contains('senderUid'), isTrue,
          reason: 'الردُّ لم يَعُدْ موقَّعاً — فتعليلُ الإعفاءِ يُراجَع');
    });

    test('(ك) حفظُ الإعداداتِ يُقيَّدُ **بعدَ** الالتزامِ لا قبلَه', () {
      // قيدٌ يَقولُ «تمَّ» عن دفعةٍ فشلت كذبٌ — والترتيبُ هو الإصلاح.
      final s = stripComments(
          File('lib/screens/admin/admin_settings_screen.dart')
              .readAsStringSync());
      final iCommit = s.indexOf('batch.commit()');
      final iAudit = s.indexOf('actionUpdateSettings');
      expect(iCommit, greaterThan(0));
      expect(iAudit, greaterThan(iCommit),
          reason: 'القيدُ قبلَ الالتزام — يُسجّلُ حفظاً قد يَفشل');
      final p = stripComments(
          File('admin_panel/src/pages/Settings.tsx').readAsStringSync());
      final pCommit = p.indexOf('batch.commit()');
      final pAudit = p.indexOf('AUDIT.UPDATE_SETTINGS');
      expect(pCommit, greaterThan(0));
      expect(pAudit, greaterThan(pCommit),
          reason: 'قيدُ اللوحةِ قبلَ الالتزام');
    });
  });
}
