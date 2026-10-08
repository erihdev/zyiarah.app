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
/// يُجرِّدُ التعليقاتِ قبلَ المسح — **وقائيٌّ لا حاملٌ، ويُقالُ كذلك**:
/// قِيسَ الفرقُ ووُجدَ **صفراً** (لا حقلَ واحدَ يَأتي من تعليقٍ اليومَ)،
/// واختبارُ قضمٍ يُجوِّفُه فلا يَسقطُ شيء. ويَبقى لأنّ «الحارسُ يَسقطُ على
/// توثيقِه» سُجِّلَ هنا اثنتَي عشرةَ مرّةً في الاتّجاهِ المُعاكس: تعليقٌ
/// يَذكرُ `where('created_at', …)` بجوارِ مجموعتِه يُبرِّرُ فهرساً ميتاً
/// بصمت، وهو عطلٌ يَصعبُ رؤيتُه بعدَ وقوعِه.
String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');

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

    test('البثُّ المجدول: الاستعلامُ يَسألُ ما تَسألُه المطالبة', () {
      // **نافذةٌ بـ`limit` تَمتلئُ بما لا يُزيلُه أحد.** كان الاستعلامُ مدًى
      // واحداً (`scheduled_at <= now`) بلا مساواةٍ على الحالة، و«الحالةُ تُصفّى
      // في الكود». ومستندُ بثٍّ **مُرسَلٍ** يَحتفظُ بـ`scheduled_at` ماضيةً
      // فيَظلُّ مطابقاً للأبد، والترتيبُ الضمنيُّ لاستعلامِ المدى هو ذلك الحقلُ
      // تصاعديّاً: فأقدمُ خمسينَ بثٍّ مُرسَلٍ تَسُدُّ النافذةَ، والمطالبةُ
      // تَنكُلُ عن كلِّ واحدٍ منها، والجديدُ الذي حلَّ موعدُه لا يُقرأُ أصلاً.
      expect(has('notifications_log', ['status', 'scheduled_at']), isTrue,
          reason: 'مساواةٌ على status مع مدًى على scheduled_at تَلزمُها هذه');

      final String fn = File('functions/index.js').readAsStringSync();
      final String code = fn
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final int at = code.indexOf('db.collection("notifications_log")\n');
      expect(at, greaterThan(-1), reason: 'استعلامُ الإفراجِ اختفى');
      final String q = code.substring(at, code.indexOf('.get();', at));
      expect(q.contains('.where("status", "==", "scheduled")'), isTrue,
          reason: 'بلا هذه المساواةِ تَعودُ النافذةُ تَمتلئُ بالمُرسَل');
      expect(q.contains('.where("scheduled_at", "<=", now)'), isTrue);

      // والمطالبةُ تَسألُ السؤالَ نفسَه — الطرفانِ يَتحرّكانِ معاً أو يَسقط.
      expect(code.contains('if (d.status !== "scheduled" || d.processed === true) return null;'),
          isTrue,
          reason: 'شرطُ المطالبةِ هو ما نُقل إلى الاستعلام');

      // **وهذا الـcron ليس شبكةَ أمانٍ لِما بَعُد عن 29 يوماً، بل مَسارُه
      // الوحيد**: `onNotificationCreated` لا يُجدولُ Cloud Task بعدها.
      expect(code.contains('29 * 24 * 60 * 60 * 1000'), isTrue,
          reason: 'إن زال الحدُّ فالاعتمادُ على الـcron يَحتاجُ مراجعة');
    });

    test('ومَن يَكتبُ scheduled_at يَكتبُ status: scheduled — المجموعةُ كلُّها',
        () {
      // التضييقُ آمنٌ ما دام كلُّ مُجدوِلٍ يَكتبُ الحالة. مُحرِّرٌ ثالثٌ
      // يَكتبُ الموعدَ وحدَه يُصبحُ غيرَ مرئيٍّ للـcron — وهو نمطُ «حقلُ قرارٍ
      // يَعرفُه مُحرِّرٌ واحد» الذي تَكرّر أربعَ مرّاتٍ في هذا المستودع.
      final writers = <String>[];
      for (final d in [Directory('lib'), Directory('admin_panel/src')]) {
        for (final f in d.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart') &&
              !f.path.endsWith('.ts') &&
              !f.path.endsWith('.tsx')) {
            continue;
          }
          if (f.path.contains('.test.')) continue;
          final String src = f.readAsStringSync();
          if (!src.contains('notifications_log')) continue;
          if (src.contains("'scheduled_at':") || src.contains('scheduled_at: ')) {
            writers.add(f.path.split('/').last);
          }
        }
      }
      expect(writers.toSet(),
          {'zyiarah_messaging_service.dart', 'Notifications.tsx'},
          reason: 'مُجدوِلٌ جديدٌ يُراجَع: هل يَكتبُ status: scheduled؟');
      expect(
          File('lib/services/zyiarah_messaging_service.dart')
              .readAsStringSync()
              .contains("'status': 'scheduled'"),
          isTrue);
      expect(
          File('admin_panel/src/pages/Notifications.tsx')
              .readAsStringSync()
              .contains("status: isScheduled ? 'scheduled'"),
          isTrue);
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

  // ───────────────────────────────────────────────────────────────────────
  // الاتّجاهُ العكسيُّ **لكلِّ** فهرسٍ لا لسبعةٍ مُسمّاة
  //
  // رأسُ هذا الملفِّ يَقولُ القاعدةَ عامّةً — «فهرسٌ بلا استعلامٍ يبرّره
  // يسقط» — وكانت مُنفَّذةً على **سبعةٍ من تسعةٍ وعشرين**، كلُّها مكتوبةٌ
  // بالاسم. فمسحٌ مُشتَقٌّ (2026-10-07) أعطى **ثمانيةَ فهارسَ لا استعلامَ
  // لها**، وثلاثةٌ منها ليست كلفةَ كتابةٍ فحسب بل **خريطةٌ خاطئةٌ لنموذجِ
  // البيانات**: `support_tickets` و`contracts` حقلُهما `createdAt` لا
  // `created_at` — و`orderBy` على حقلٍ **غائبٍ تُسقِطُ المستندَ من النتيجة**،
  // فاستعلامٌ يُكتَبُ غداً بحسنِ نيّةٍ على الفهرسِ المُعلَنِ يُعيدُ قائمةً
  // فارغةً بلا خطأ. وهو شكلُ `src/types/index.ts` الذي حُذفَ هنا: خريطةٌ
  // متّسقةٌ مع نفسِها ومخالفةٌ للواقع.
  group('كلُّ فهرسٍ مُعلَنٍ يُبرِّرُه استعلام', () {
    /// حقولُ كلِّ مجموعةٍ كما تُستعلَمُ فعلاً — **بحدِّ الجملةِ** لا بنافذةِ
    /// عدِّ أحرف (فخُّ الحدِّ مسجَّلٌ هنا عشرَ مرّات): سلسلةُ Firestore تَنتهي
    /// عند `;` على عمقِ صفر، وفي TypeScript عند قوسِ `query(` المُوازَن.
    Map<String, Set<String>> queriedFields() {
      final out = <String, Set<String>>{};
      final fld = RegExp(
          r'''(?:where|orderBy|sum|average)\(\s*['"]([A-Za-z_][A-Za-z0-9_.]*)['"]''');
      final col = RegExp(
          r'''\.?collection\(\s*(?:db\s*,\s*)?['"]([a-z_]+)['"]\s*\)''');

      int stmtEnd(String s, int i) {
        var d = 0;
        final lim = (i + 1200).clamp(0, s.length);
        for (var j = i; j < lim; j++) {
          final c = s[j];
          if (c == '(' || c == '[' || c == '{') {
            d++;
          } else if (c == ')' || c == ']' || c == '}') {
            d--;
          } else if (c == ';' && d <= 0) {
            return j;
          }
        }
        return lim;
      }

      for (final dir in ['lib', 'functions', 'admin_panel/src']) {
        for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
          final path = f.path.replaceAll('\\', '/');
          if (path.contains('/node_modules/')) continue;
          if (path.contains('.test.')) continue;
          if (!(path.endsWith('.dart') ||
              path.endsWith('.js') ||
              path.endsWith('.ts') ||
              path.endsWith('.tsx'))) {
            continue;
          }
          final src = _strip(f.readAsStringSync());
          final isTs = path.endsWith('.ts') || path.endsWith('.tsx');
          for (final m in col.allMatches(src)) {
            String seg;
            if (isTs) {
              final q = src.lastIndexOf('query(', m.start);
              if (q < 0) {
                seg = src.substring(m.start, stmtEnd(src, m.end));
              } else {
                var d = 0;
                var j = q + 'query('.length;
                while (j < src.length) {
                  final c = src[j];
                  if (c == '(') {
                    d++;
                  } else if (c == ')') {
                    if (d == 0) break;
                    d--;
                  }
                  j++;
                }
                seg = src.substring(q, j);
              }
            } else {
              seg = src.substring(m.start, stmtEnd(src, m.end));
            }
            for (final fm in fld.allMatches(seg)) {
              (out[m.group(1)!] ??= <String>{}).add(fm.group(1)!);
            }
          }
        }
      }
      return out;
    }

    /// فهرسٌ لا يَراه المسحُ، **ولكلٍّ سببُه**. المفتاحُ `مجموعة|حقول`.
    ///
    /// الستّةُ الأُولى مُبرَّرةٌ فعلاً ولا يَراها مسحٌ بالاسم؛ والثمانيةُ
    /// الباقيةُ **بلا استعلامٍ أصلاً** وتَنتظرُ حذفاً بشريّاً —
    /// كقائمةِ `functions_delete_once.yml`.
    ///
    /// **ولمَ لا تُحذَفُ من هنا — التعليلُ صُحِّحَ في 2026-10-08.** كان هذا
    /// الموضعُ يَقولُ إنّ إزالتَها «تُخاطِرُ بتعطيلِ مسارِ النشرِ لأنّه بلا
    /// `--force`» قياساً على نشرِ الدوالّ، وإنّ سلوكَ `firebase-tools` «لا
    /// يُمكِنُ التحقّقُ منه من هذه البيئة» — **وكان يُمكِن**: المصدرُ في
    /// `node_modules`. والسلوكُ الحقيقيُّ أنّ الأداةَ بـ`--non-interactive`
    /// وبلا `--force` **تُسجّلُ وتُكمِلُ بنجاح** ولا تَفشلُ ولا تَحذف
    /// (`lib/firestore/api.js`: الفرعُ يَطبعُ «To delete them, run this
    /// command with the `--force` flag» ثمّ يُنادي
    /// `confirm({nonInteractive, force, default: false})`، و`lib/prompt.js`
    /// يُعيدُ الافتراضَ المُعلَنَ ولا يَرمي). فالتبعتانِ غيرُ ما كُتِب:
    ///
    /// 1. إزالتُها من `firestore.indexes.json` **لا تَحذفُها من الإنتاج** —
    ///    تَجعلُ الملفَّ يَكُفُّ عن وصفِ الإنتاجِ، وهو أسوأُ من بقائها.
    /// 2. والحذفُ الآليُّ الوحيدُ `--force`، ويَحذفُ في المرورِ نفسِه **كلَّ
    ///    تجاوزِ حقلٍ** قائمٍ في الإنتاجِ وغائبٍ عن الملفّ (فرعٌ مستقلٌّ في
    ///    المصدرِ نفسِه: `shouldDeleteFields = options.force`) — والملفُّ
    ///    يُعلِنُ `fieldOverrides: []`، فتجاوزٌ أحاديٌّ ضُبطَ من الكونسولِ
    ///    يَزولُ معها. فذاك هو الخطرُ الحقيقيّ، وهو خطرٌ آخرُ غيرُ المكتوبِ
    ///    أوّلاً.
    ///
    /// فالمَخرَجُ بيدٍ، بعد فحصِ الكونسول: إزالةُ الثمانيةِ من الملفِّ **ثمّ**
    /// `npx firebase-tools@15 deploy --only firestore:indexes --project
    /// zyiarah-app --force`. والانحرافُ نفسُه كان سطراً في سجلٍّ لا يُقرَأُ من
    /// الـAPI، فصارَ يُنشَرُ في ملخَّصِ وظيفةِ النشرِ بعددِه.
    const Map<String, String> justification = {
      // (أ) حقلُ التجميعِ لا يَظهرُ في `where`/`orderBy` — مشدودٌ بفحوصِه
      //     المُسمّاةِ في أوّلِ هذا الملفّ.
      'orders|status,amount': 'تجميع sum — مشدودٌ بفحصِه أعلاه',
      'orders|status,service_meta.kind,amount':
          'تجميع sum — مشدودٌ بفحصِه أعلاه',
      'store_orders|is_paid,total_amount': 'تجميع sum — مشدودٌ بفحصِه أعلاه',
      'store_orders|status,total_amount': 'تجميع sum — مشدودٌ بفحصِه أعلاه',
      // (ب) اسمُ المجموعةِ **مُتغيّرُ حلقةٍ** في مكنسةِ إعادةِ الطابورَين،
      //     فلا مسحٌ بالاسمِ يَراه — ومشدودٌ بفحصِه المُسمّى أعلاه.
      'notification_triggers|processed,createdAt':
          'اسمُ المجموعةِ مُتغيّرُ حلقة — مشدودٌ بفحصِه أعلاه',
      'notification_queue|processed,createdAt':
          'اسمُ المجموعةِ مُتغيّرُ حلقة — مشدودٌ بفحصِه أعلاه',
      // (ج) بلا استعلامٍ أصلاً — مُعلَّقةٌ لحذفٍ بشريّ (2026-10-07).
      //     والعددُ لا يُكتَبُ هنا: `deploy_guide_accuracy_test` يَشتقُّه
      //     من هذه المُدخَلاتِ بعينِها ويُقابِلُه بالدليل، ونسخةٌ ثانيةٌ
      //     تَنحرِفُ (كما انحرفَ عددُ محجوزاتِ STAGE-C).
      'support_tickets|userId,created_at':
          'الحقلُ `createdAt` لا `created_at` — خريطةٌ خاطئة، بلا استعلام',
      'support_tickets|status,created_at':
          'الحقلُ `createdAt` لا `created_at` — خريطةٌ خاطئة، بلا استعلام',
      'contracts|userId,created_at':
          'الحقلُ `createdAt` لا `created_at` — خريطةٌ خاطئة، بلا استعلام',
      'notifications|userId,isRead,sentAt':
          '`isRead` يُرشَّحُ محلّيّاً بقرارٍ قائمٍ ولا يُستعلَمُ — بلا استعلام',
      'audit_logs|admin_email,timestamp':
          'الاستعلامُ `orderBy(timestamp)` وحدَه — بلا استعلام',
      'account_deletions|status,requested_at':
          'الاستعلامُ `orderBy(requested_at)` وحدَه — بلا استعلام',
      'maintenance_requests|userId,status':
          'الصيانةُ أُزيلت من الجذر؛ ما بقي قراءةٌ بالمعرّفِ وبحثٌ على `code` — بلا استعلام',
      'maintenance_requests|userId,created_at':
          'الصيانةُ أُزيلت من الجذر؛ ما بقي قراءةٌ بالمعرّفِ وبحثٌ على `code` — بلا استعلام',
    };

    final Map<String, Set<String>> used = queriedFields();

    test('المسحُ أصابَ فعلاً — لا فحصٌ أجوف', () {
      // استخراجٌ يَنحلُّ إلى فراغٍ يَجعلُ كلَّ فهرسٍ «بلا استعلام» فتَمتلئُ
      // قائمةُ الاستثناءِ بالباطل، أو — لو قُلِبت المقارنة — يُقرأُ نظيفاً.
      expect(used.length, greaterThanOrEqualTo(20),
          reason: 'لم تُستخرَج المجموعات');
      expect(used.values.fold<int>(0, (a, b) => a + b.length),
          greaterThanOrEqualTo(60), reason: 'لم تُستخرَج الحقول');
      expect(used['orders'], containsAll(<String>['status', 'service_date']));
      // وهذا بعينُه ما يُثبِتُ دعوى «الحقلُ camelCase»: المسحُ يَرى
      // `createdAt` على المجموعتَين ولا يَرى `created_at`.
      expect(used['support_tickets'], contains('createdAt'));
      expect(used['support_tickets']?.contains('created_at') ?? false, isFalse,
          reason: 'لو ظهرَ `created_at` فالفهرسانِ مُبرَّرانِ ويُراجَعُ التعليل');
      expect(used['contracts'], contains('createdAt'));
      expect(used['contracts']?.contains('created_at') ?? false, isFalse);
    });

    test('كلُّ فهرسٍ إمّا يُستعلَمُ أو مُعلَّلٌ بالاسم', () {
      final unexplained = <String>[];
      final stale = <String>[];
      final keys = <String>{};
      for (final dynamic raw in indexes) {
        final i = raw as Map<String, dynamic>;
        final col = i['collectionGroup'] as String;
        final fields = (i['fields'] as List<dynamic>)
            .map((dynamic x) => (x as Map<String, dynamic>)['fieldPath'] as String)
            .toList();
        final key = '$col|${fields.join(',')}';
        keys.add(key);
        final seen = used[col] ?? const <String>{};
        final missing = fields.where((f) => !seen.contains(f)).toList();
        if (missing.isEmpty) continue;
        if (!justification.containsKey(key)) unexplained.add('$key  ← $missing');
      }
      // والقائمةُ لا تَتعفّن: مُدخَلٌ لفهرسٍ زال، أو لفهرسٍ صارَ مُستعلَماً.
      for (final k in justification.keys) {
        if (!keys.contains(k)) stale.add('$k (لا فهرسَ بهذا الاسم)');
      }
      expect(unexplained, isEmpty,
          reason: '\n\nفهرسٌ بلا استعلامٍ يبرّره ولا سببٍ مكتوب:\n  • '
              '${unexplained.join('\n  • ')}\n');
      expect(stale, isEmpty,
          reason: '\n\nمُدخَلٌ في قائمةِ التعليلِ لم يَعُد له فهرس:\n  • '
              '${stale.join('\n  • ')}\n');
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

    test('انحرافُ الملفِّ عن الإنتاجِ يُنشَرُ بعددِه، لا يَبقى سطراً في سجلّ',
        () {
      // بـ`--non-interactive` وبلا `--force` تَطبعُ الأداةُ «there are N
      // indexes defined in your project that are not present in your
      // firestore indexes file» ثمّ **تُكمِلُ بنجاح** — فالانحرافُ لا يُفشِلُ
      // شيئاً ولا يُرى: سجلُّ التشغيلِ يُخدَمُ من مُضيفٍ آخرَ ولا يُقرأُ من
      // الـAPI (نفسُ سببِ خطوةِ «Surface the failure»). والثمانيةُ المُعلَّقةُ
      // أعلاه لا تُراجَعُ إلّا بعددٍ مقروء.
      final int iDep = wf.indexOf('      - name: Deploy');
      final int iRep = wf.indexOf('      - name: Report file ↔ project divergence');
      expect(iDep, greaterThan(-1), reason: 'خطوةُ النشرِ اختفت');
      expect(iRep, greaterThan(-1),
          reason: 'خطوةُ الإبلاغِ عن الانحرافِ اختفت — فالعددُ يَعودُ غيرَ مقروء');
      expect(iDep, lessThan(iRep),
          reason: 'الإبلاغُ يَقرأُ سجلَّ النشر، فلا يَسبقُه');

      final int next = wf.indexOf('      - name:', iRep + 10);
      final String step = wf.substring(iRep, next < 0 ? wf.length : next);
      expect(step.contains(r'$RUNNER_TEMP/deploy.log'), isTrue,
          reason: 'الاقتطاعُ لم يُصِب الخطوةَ — فحصٌ أجوف');
      expect(step.contains('if: success()'), isTrue,
          reason: 'بلا `if: success()` يَعملُ على نشرٍ فاشلٍ فيُبلِغُ عن سجلٍّ '
              'مقطوعٍ — و«Surface the failure» هي صاحبةُ ذلك المسار');
      // كلا العددَين: الفهارسُ **وتجاوزاتُ الحقول**. الثاني هو ما يَجعلُ
      // الحذفَ اليدويَّ خطِراً (انظر تعليلَ القائمةِ أعلاه)، فإسقاطُه يُخفي
      // الخطرَ الذي يُحذّرُ منه النصُّ نفسُه.
      expect(step.contains('indexes defined in your project'), isTrue,
          reason: 'عددُ الفهارسِ الزائدةِ لا يُقرَأ');
      expect(step.contains('field overrides defined in your project'), isTrue,
          reason: 'عددُ تجاوزاتِ الحقولِ لا يُقرَأ — وهو ما يُفقَدُ بـ`--force`');
      expect(step.contains(r'$GITHUB_STEP_SUMMARY'), isTrue,
          reason: 'الخَرْجُ إلى سجلٍّ لا يُقرَأُ من الـAPI = لا شيء');
      // والمَخرَجُ اليدويُّ يُطبَعُ كاملاً: أمرٌ بلا `--project` يَنشرُ إلى
      // مشروعٍ آخر، وبلا `--force` لا يَحذفُ شيئاً فتُقرأُ الخطوةُ عاجزة.
      // **والعَلَمانِ مشدودانِ معاً بنصِّ سطرِ الأمر، لا كلٌّ وحدَه:** نصُّ
      // الخطوةِ يَشرحُ القرارَ بذكرِ `--force` في جملةٍ عاديّةٍ، فاختبارُ
      // قضمٍ نزعَ العلَمَ من **الأمرِ** مرَّ أخضرَ — «موضعٌ آخرُ يُرضي
      // الفحصَ»، والعلاجُ شدُّ شكلِ الأمرِ لا حضورِ الاسم.
      expect(step.contains('--only firestore:indexes'), isTrue,
          reason: 'المَخرَجُ اليدويُّ بلا `--only` يَنشرُ القواعدَ (حجزُ STAGE-C)');
      expect(step.contains('--project zyiarah-app --force'), isTrue,
          reason: 'أمرُ المَخرَجِ اليدويِّ ناقصٌ: بلا `--project` يَستهدفُ ما '
              'تَختارُه البيئةُ، وبلا `--force` لا يَحذفُ شيئاً');
    });

    test('ولا حذفَ من المسار — فدعوى الخطوةِ صادقة', () {
      // النصُّ يَقولُ «حذفُها **لا يَجري من هنا**»، وصدقُه شرطُه أن يَبقى
      // نداءُ النشرِ بلا `--force`. والفحصُ **مقصورٌ على نداءِ النشر**: نصُّ
      // الخطوةِ يَطبعُ الأمرَ اليدويَّ وفيه العلَمُ — وهو **شفرةٌ لا تعليق**،
      // فلا يَحجبُها تجريدُ التعليقاتِ (نفسُ ما أسقطَ أوّلَ نسخةٍ من حارسِ
      // نشرِ الدوالّ).
      final int iDep = wf.indexOf('      - name: Deploy');
      final int next = wf.indexOf('      - name:', iDep + 10);
      // **وتجريدُ التعليقاتِ حاملٌ لا زينة، وهذا الفحصُ أثبتَه.** حدُّ
      // الخطوةِ هو سطرُ اسمِ التاليةِ، وتعليقاتُ YAML للخطوةِ التاليةِ
      // تَسكنُ **فوقَ** ذلك السطرِ — فتَقعُ في شريحةِ السابقة. وتعليقُ
      // خطوةِ الإبلاغِ يَشرحُ القرارَ بذكرِ `--force`، فأوّلُ صياغةٍ لهذا
      // الفحصِ سقطت على توثيقِها هي (الفخُّ المسجَّلُ في `CLAUDE.md`، بحدٍّ
      // جديد). والمضادّةُ تَحتَه: العلَمُ ما زال في النصِّ الخامّ.
      final String deployStep = wf
          .substring(iDep, next < 0 ? wf.length : next)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(deployStep.contains('firebase-tools'), isTrue,
          reason: 'الاقتطاعُ لم يُصِب نداءَ النشر — فحصٌ أجوف');
      expect(deployStep.contains('--non-interactive'), isTrue,
          reason: 'سؤالٌ تفاعليٌّ في CI تعليقٌ حتى المهلة');
      expect(deployStep.contains('--force'), isFalse,
          reason: 'بـ`--force` يَحذفُ المسارُ الفهارسَ **وكلَّ تجاوزِ حقلٍ** '
              'غائبٍ عن الملفّ — وهو قرارٌ بشريٌّ يُجرى بيدٍ مرّةً');
      // **ولا مضادّةَ هنا، بقصد.** العلاجُ المعتادُ («جرِّدْ ثمّ أثبِتْ أنّ
      // المصطلحَ ما زال في الخامّ») لا يُفيدُ: ما يَبقى بعد التجريدِ هو
      // العلَمُ في **شفرةِ** خطوةِ الإبلاغِ، وهو مشدودٌ في الفحصِ أعلاه
      // أصلاً — فمضادّةٌ على الملفِّ كلِّه لا يُمكِنُ أن تَسقطَ وحدَها. وما
      // يُثبِتُ أنّ التجريدَ حاملٌ هو اختبارُ قضمٍ يَنزِعُه: بلاهُ يَسقطُ
      // هذا الفحصُ على تعليقِ الخطوةِ التالية.
    });

    test('والملفُّ يُعلِنُ `fieldOverrides: []` — فتحذيرُ الحذفِ صادق', () {
      // تعليلُ القائمةِ أعلاه ونصُّ الخطوةِ كلاهما يَقولُ إنّ `--force`
      // اليدويَّ يَمحو تجاوزاتِ الحقولِ **لأنّ الملفَّ لا يُعلِنُ أيّاً منها**.
      // فلو أُعلِنَ تجاوزٌ يوماً فالتحذيرُ يُراجَعُ لا يُسكَت.
      final dynamic fo = idx['fieldOverrides'];
      expect(fo, isA<List<dynamic>>(),
          reason: 'المفتاحُ غابَ — فالمصدرُ لم يَعُدْ كما يَصفُه التعليل');
      expect((fo as List<dynamic>), isEmpty,
          reason: 'صارَ للملفِّ تجاوزُ حقلٍ: راجِعْ تحذيرَ `--force` في '
              'قائمةِ التعليلِ وفي خطوةِ الإبلاغ');
    });

    test('المفتاحُ من سرٍّ ويُمحى حتى عند الفشل', () {
      expect(wf.contains(r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'), isTrue);
      expect(wf.contains('if: always()'), isTrue);
      expect(wf.contains('rm -f'), isTrue);
      expect(wf.contains('::error::'), isTrue);
    });
  });
}
