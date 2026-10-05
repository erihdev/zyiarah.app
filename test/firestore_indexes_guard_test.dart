import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// فهارسُ التجميع، ونشرُها.
///
/// **التجميعُ ليس استعلاماً عاديّاً.** `Dashboard.tsx` يحسب الإيراد بـ`sum()`،
/// وتعليقُه كان يقول «استعلامان بمساواة فقط (لا فهرس مركّب)» — وهذا صحيحٌ
/// للاستعلام العادي (دمجُ zigzag على الفهارس الأحادية) و**خطأٌ للتجميع**:
/// `sum()`/`average()` يلزمهما فهرسٌ مركّبٌ يشمل الحقلَ المجموع. فظهرت على
/// اللوحة لافتةُ «تعذّر تحميل بعض الإحصائيات» والإيرادُ `•••`، بينما بقيةُ
/// الأرقام (عدّادات `count()` بلا حقلٍ مجموع) تصل سليمة.
///
/// وCLAUDE.md يحذّر من إضافة فهارس مركّبة باستخفاف — فهذه الأربعة مشدودةٌ هنا
/// إلى مواضع استعمالها: فهرسٌ بلا استعلامٍ يبرّره يسقط، واستعلامُ `sum()` بلا
/// فهرسٍ يسقط كذلك.
void main() {
  final Map<String, dynamic> idx = jsonDecode(
      File('firestore.indexes.json').readAsStringSync()) as Map<String, dynamic>;
  final List<dynamic> indexes = idx['indexes'] as List<dynamic>;

  /// هل يوجد فهرسٌ على [group] يحوي هذه الحقول بهذا الترتيب؟
  bool has(String group, List<String> fields) => indexes.any((dynamic raw) {
        final i = raw as Map<String, dynamic>;
        if (i['collectionGroup'] != group) return false;
        final f = (i['fields'] as List<dynamic>)
            .map((dynamic x) => (x as Map<String, dynamic>)['fieldPath'])
            .toList();
        return f.length == fields.length &&
            List.generate(fields.length, (n) => f[n] == fields[n])
                .every((b) => b);
      });

  final String dash =
      File('admin_panel/src/pages/Dashboard.tsx').readAsStringSync();

  group('فهارسُ التجميع موجودة', () {
    test('إيرادُ الطلبات: status + amount', () {
      expect(has('orders', ['status', 'amount']), isTrue,
          reason: "sum('amount') مع status == 'completed' يلزمه هذا الفهرس");
    });

    test('إيرادُ المتجر المطروح: status + service_meta.kind + amount', () {
      expect(has('orders', ['status', 'service_meta.kind', 'amount']), isTrue,
          reason: 'الحقلُ المجموع يأتي آخراً بعد حقول المساواة');
    });

    test('إيرادُ طلبات المتجر: شقّا or() لكلٍّ فهرسه', () {
      // `or(is_paid==true, status in [...])` يُقسَم خادميّاً إلى استعلامين.
      expect(has('store_orders', ['is_paid', 'total_amount']), isTrue);
      expect(has('store_orders', ['status', 'total_amount']), isTrue);
    });
  });

  group('الفهارسُ مشدودةٌ إلى استعمالها', () {
    test('اللوحة ما زالت تجمع هذه الحقول بعينها', () {
      // فهرسٌ يبقى بعد زوال استعلامه = كلفةُ كتابةٍ بلا مقابل؛ واستعلامٌ يتغيّر
      // حقلُه المجموع يحتاج فهرساً آخر. الطرفان يتحرّكان معاً أو يسقط الفحص.
      expect(dash.contains("sum('amount')"), isTrue);
      expect(dash.contains("sum('total_amount')"), isTrue);
      expect(dash.contains("where('status', '==', 'completed')"), isTrue);
      expect(dash.contains("where('service_meta.kind', '==', 'store_products')"),
          isTrue);
      expect(dash.contains("where('is_paid', '==', true)"), isTrue);
    });

    test('طابورا الإشعارات: فهرسٌ لكلِّ مجموعةٍ لا فهرسٌ مُشترَك', () {
      // **الفهارسُ في Firestore لكلِّ مجموعةٍ على حِدة.** `opsHealthSweep`
      // يُعيدُ دفعَ الإشعاراتِ العالقةِ باستعلامٍ مركَّب — مساواةٌ على
      // `processed`، ومدًى وترتيبٌ على `createdAt` — ثم صار يَمسحُ الطابورَين.
      // وكان الفهرسُ موجوداً لـ`notification_triggers` وحدَه، فاستعلامُ
      // `notification_queue` (حيث تَحيا كلُّ إشعاراتِ `queuePush` الآن) يَسقط.
      expect(has('notification_triggers', ['processed', 'createdAt']), isTrue);
      expect(has('notification_queue', ['processed', 'createdAt']), isTrue,
          reason: 'الطابورُ الخادميُّ يَحملُ كلَّ إشعاراتِ queuePush');
    });

    test('والاستعلامُ ما زال يَمسحُ الطابورَين — وبـtry لكلِّ مجموعة', () {
      // فهرسٌ يبقى بعد زوالِ استعلامِه = كلفةُ كتابةٍ بلا مقابل؛ والعكسُ
      // أسوأ. والطرفانِ يَتحرّكانِ معاً أو يَسقطُ الفحص.
      final String fn = File('functions/index.js').readAsStringSync();
      final String code = fn
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
          code.contains(
              'for (const col of ["notification_queue", "notification_triggers"]) {'),
          isTrue,
          reason: 'إن تغيّرت المجموعاتُ الممسوحةُ فالفهارسُ تَتبعها');
      expect(code.contains('.where("processed", "==", false)'), isTrue);
      expect(code.contains('.orderBy("createdAt", "asc")'), isTrue);

      // **`try` داخلَ الحلقةِ لا حولَها.** كان واحداً يُحيط بها
      // و`notification_queue` أوّلَها، فنقصُ فهرسٍ في الأولى يَقطعُ الحلقةَ
      // قبلَ الثانيةِ: شبكةُ الأمانِ تَموتُ للطابورَين بسببِ واحد.
      final int loopAt = code.indexOf(
          'for (const col of ["notification_queue", "notification_triggers"]) {');
      final int tryAt = code.indexOf('try {', loopAt);
      final int qAt = code.indexOf('.where("processed", "==", false)', loopAt);
      expect(tryAt > loopAt && tryAt < qAt, isTrue,
          reason: '`try` يَلزمُ أن يكونَ داخلَ الحلقةِ قبلَ الاستعلام');
      expect(code.contains(r'`opsHealthSweep: redrive ${col} failed:`'), isTrue,
          reason: 'والفشلُ يُسمّي مجموعتَه، وإلّا فلا يُعرَفُ أيُّهما سقط');

      // والتشخيصُ اليدويُّ يَقرأُ الطابورَين كذلك — طابورٌ واحدٌ يَقولُ
      // «صفرٌ معلَّق» بينما الآخرُ مُتراكم.
      //
      // ويُجرَّدُ من التعليقِ أوّلاً: اختبارُ القضمِ أعادَ المجموعةَ الواحدةَ
      // ومرَّ الفحصُ أخضرَ، لأنّ التعليقَ الشارحَ يُسمّي `notification_queue`.
      final String diagRaw =
          File('functions/diagnose_email.js').readAsStringSync();
      final String diag = diagRaw
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
          diag.contains(
              'for (const col of ["notification_queue", "notification_triggers"]) {'),
          isTrue,
          reason: 'التشخيصُ يُشغَّلُ حين يَتعطّلُ البريد — فيَلزمُه الطابوران');
      // وبالمقابل: اللفظُ ما زال في الخامّ، فلا يُجرّدُ الفحصُ نفسَه فراغاً.
      expect(diagRaw.contains('notification_queue'), isTrue);
    });

    test('لا فهرسَ مكرّر', () {
      final seen = <String>{};
      for (final dynamic raw in indexes) {
        final i = raw as Map<String, dynamic>;
        final k = '${i['collectionGroup']}|'
            '${(i['fields'] as List<dynamic>).map((dynamic x) => (x as Map<String, dynamic>)['fieldPath']).join(',')}';
        expect(seen.add(k), isTrue, reason: 'فهرسٌ مكرّر: $k');
      }
    });
  });

  group('نشرُ الفهارس', () {
    final String wf = File('.github/workflows/firestore_indexes_deploy.yml')
        .readAsStringSync();
    final String code = wf
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');

    test('يعمل عند تغيّر ملفّ الفهارس', () {
      expect(wf.contains("- 'firestore.indexes.json'"), isTrue);
      expect(wf.contains('workflow_dispatch:'), isTrue);
      expect(wf.contains('--only firestore:indexes'), isTrue);
      expect(wf.contains('--project zyiarah-app'), isTrue);
    });

    test('**لا ينشر القواعد** — قرارٌ بشريٌّ مرتبطٌ بانتشار الإصدار', () {
      // `firestore.rules` يحمل STAGE-C: قاعدةُ الإنشاء الجديدة تكسر مدفوعاتِ
      // النسخ القديمة من التطبيق، فلا تُنشر إلّا بعد فرض الحدّ الأدنى للإصدار.
      expect(code.contains('firestore:rules'), isFalse,
          reason: 'نشرُ القواعد من دمجةٍ قد يكسر مدفوعاتِ النسخ القديمة');
      expect(code.contains('--only firestore '), isFalse,
          reason: '`--only firestore` يشمل القواعد ضمناً');
      // التحذيرُ نفسه ما زال في مكانه؛ لو أُزيل فالسببُ أعلاه بحاجة لمراجعة.
      final String rules = File('firestore.rules').readAsStringSync();
      expect(rules.contains('STAGE-C'), isTrue,
          reason: 'اختفى تحذيرُ STAGE-C — أعِد تقييم منعِ نشر القواعد');
      // والحارسُ يذكر القواعد في تعليقه، فلولا التجريد لسقط على توثيقه.
      expect(wf.contains('firestore.rules'), isTrue,
          reason: 'شرحُ القرار اختفى من رأس الملفّ');
    });

    test('المفتاحُ من سرٍّ ويُمحى حتى عند الفشل', () {
      expect(wf.contains(r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'), isTrue);
      expect(wf.contains('if: always()'), isTrue);
      expect(wf.contains('rm -f'), isTrue);
      expect(wf.contains('::error::'), isTrue);
    });
  });
}
