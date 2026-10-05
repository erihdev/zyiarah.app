import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **ادّعاءٌ في رأسِ ملفٍّ بلا قارئ.** `admin_panel/src/config/access.ts`
/// يَقولُ عن نفسِه:
///
/// > Kept in sync with firestore.rules and the Cloud Functions' `_assertAdmin`
/// > checks **so a role never sees a page whose actions the backend would
/// > reject**.
///
/// ولا شيءَ كان يَقرأُ ذلك. `App.split.test.ts` يَشدُّ المسارَ إلى الخريطةِ في
/// الاتجاهَين — أي أنّ كلَّ صفحةٍ مُجدوَلةٌ ومُقسَّمة — أمّا مطابقةُ الخريطةِ
/// بـ`firestore.rules` فلم يَفحصْها فحصٌ قطّ. فافترقَتا:
///
///   • `/contracts` كان لـ`orders_manager` وحدَه، والصفحةُ تَحملُ **ثلاثَ
///     مِلكيّات**: العقودُ (`contracts` update = `isOrdersManager`) ومحرِّرا
///     باقاتِ الاشتراكِ وعاملاتِ المناسبات (write = `isMarketingAdmin`). فمديرُ
///     الطلباتِ يَرى محرّرَي الباقاتِ وكلُّ حفظٍ وحذفٍ يُرفَض، والمسوّقُ — الدورُ
///     الذي عيّنته القواعدُ — **لا يَبلغُ الصفحةَ أصلاً**. وتطبيقُ الإدارةِ
///     يَحصرُ المحرّرَين في `['super_admin','marketing_admin']` فاللوحةُ هي
///     الشاذّة.
///   • وزرُّ «حذف السجل» للعقدِ: `contracts` delete = `isSuperAdmin` («العملياتُ
///     المدمّرة» بنصِّ تعليقِ القواعد)، فكان حوارَ تأكيدٍ ثم `permission-denied`
///     حتماً لمدير الطلبات. شاشةُ Flutter تُخفيه بـ`_canDeleteContracts`
///     وتُوثّقُ السبب — اللوحةُ هي الشاذّةُ هنا أيضاً.
///
/// فهذا الفحصُ هو القارئ: يَستخرجُ أدوارَ كلِّ مُعينٍ (`isX()`) من القواعد،
/// وأفعالَ الكتابةِ المسموحةَ لكلِّ مجموعة، وما تَكتبُه كلُّ صفحةٍ فعلاً، ثم
/// يُقارِنُ **مجموعةَ المخالفاتِ كاملةً** بقائمةٍ مُعلَنةٍ لكلٍّ سببُها — فلا
/// مخالفةٌ جديدةٌ تَمرّ، ولا قائمةٌ تَتعفّنُ بعد إصلاحِ ما فيها.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// أسطرُ التعليقِ تُحذف: القواعدُ تَشرحُ قراراتَها بذكرِ أسماءِ المُعينات.
  String stripSlashComments(String src) => src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  final String rulesRaw = read('firestore.rules');
  final String rules = stripSlashComments(rulesRaw);

  // ── (أ) مُعينُ الدور → مجموعةُ الأدوار ───────────────────────────────────
  final Map<String, Set<String>> helpers = {};
  for (final m in RegExp(r'function (is\w+)\(\)\s*\{([\s\S]*?)\n\s*\}')
      .allMatches(rules)) {
    final roles = <String>{};
    for (final r in RegExp(r'getUserRole\(\) in \[([^\]]*)\]')
        .allMatches(m.group(2)!)) {
      roles.addAll(r
          .group(1)!
          .split(',')
          .map((x) => x.trim().replaceAll("'", '').replaceAll('"', ''))
          .where((x) => x.isNotEmpty));
    }
    helpers[m.group(1)!] = roles;
  }
  final Set<String> allRoles = helpers['isAdmin'] ?? <String>{};

  // ── (ب) المجموعة → الفعل → الأدوارُ المسموحة ─────────────────────────────
  /// يَقتطعُ جسمَ كتلةٍ بمطابقةِ الأقواسِ، ويَطرحُ كتلَ `match` المتداخلةَ
  /// (المجموعاتُ الفرعيّةُ قواعدُها قواعدُها لا قواعدُ الأب).
  String blockBody(String src, int openBraceIdx) {
    var depth = 1;
    var j = openBraceIdx + 1;
    while (j < src.length && depth > 0) {
      if (src[j] == '{') depth++;
      if (src[j] == '}') depth--;
      j++;
    }
    final body = src.substring(openBraceIdx + 1, j - 1);
    final out = StringBuffer();
    var k = 0;
    while (true) {
      final nested = body.indexOf('match /', k);
      if (nested < 0) {
        out.write(body.substring(k));
        break;
      }
      out.write(body.substring(k, nested));
      var d = 0;
      var p = nested;
      while (p < body.length) {
        if (body[p] == '{') d++;
        if (body[p] == '}') {
          d--;
          if (d == 0) break;
        }
        p++;
      }
      k = p + 1;
    }
    return out.toString();
  }

  final Map<String, Map<String, Set<String>>> colls = {};
  for (final m in RegExp(r'match /(\w+)/\{\w+\}\s*\{').allMatches(rules)) {
    final body = blockBody(rules, m.end - 1);
    final per = <String, Set<String>>{};
    for (final stmt in body.split(';')) {
      final am = RegExp(r'allow\s+([\w\s,]+?):\s*if\s').firstMatch(stmt);
      if (am == null) continue;
      final names = RegExp(r'\b(is\w+)\(')
          .allMatches(stmt)
          .map((x) => x.group(1)!)
          .toSet();
      var roles = <String>{};
      for (final n in names) {
        roles.addAll(helpers[n] ?? <String>{});
      }
      // **التمييزُ الذي أسقطَ أوّلَ صياغةٍ لهذا الفحص:**
      //
      //   `request.resource.data.X == request.auth.uid`  إسنادٌ ذاتيّ — كلُّ
      //      مُسجَّلٍ دخولاً يُرضيه بوسمِ uid نفسِه، فهو **أعمى عن الدور**
      //      (مثالُه `notification_triggers.createdBy`).
      //   `resource.data.X == request.auth.uid`  مِلكيّةٌ للمستندِ القائم —
      //      إداريٌّ ليس المالكَ لا يُرضيها، فالشرطُ **لا يُجيزُ دوراً**
      //      (مثالُه شرطُ السائقِ على `orders`: `resource.data.driver_id`).
      //
      // وأوّلُ صياغةٍ عدّت «`isLoggedIn()` وحدَه» إجازةً للجميعِ بلا هذا
      // التمييز، فقالت إنّ تحديثَ `orders` مُباحٌ للأدوارِ الخمسةِ — واختبارُ
      // القضمِ مرَّ أخضرَ على منحِ المحاسبِ صفحةَ الطلبات. والصياغةُ الثانيةُ
      // منعت كلَّ `request.auth.uid` فقالت إنّ `notification_triggers` لا
      // يَكتبُها أحد.
      final owned = stmt.replaceAll('request.resource.data', '')
          .contains('resource.data');
      if (names.difference({'isLoggedIn'}).isEmpty &&
          names.contains('isLoggedIn') &&
          !owned) {
        roles = {...roles, ...allRoles};
      }
      if (RegExp(r'if\s+false').hasMatch(stmt)) roles = <String>{};
      for (final v in am.group(1)!.split(',').map((x) => x.trim())) {
        per.putIfAbsent(v, () => <String>{}).addAll(roles);
      }
    }
    colls[m.group(1)!] = per;
  }

  // ── (ج) الصفحة → ما تَكتبُه فعلاً ────────────────────────────────────────
  // **ويُلتقَطُ ما داخلَ المعامَلاتِ والدفعاتِ أيضاً.** أوّلُ صياغةٍ عرفت
  // الدوالَّ الأربعَ المستقلّةَ وحدَها، فلم تَرَ `tx.update(ref, …)` في
  // `Orders.tsx` ولا `batch.update(doc(db,'service_zones',…), …)` في
  // `Settings.tsx`. لم يَتغيّر الحكمُ (المجموعتانِ مشمولتانِ من كتاباتٍ أخرى
  // في الصفحتَين نفسِهما) لكنّ حارساً لا يَرى نصفَ أساليبِ الكتابةِ ليس
  // القارئَ الذي يَدّعيه.
  const verbOf = {
    'addDoc': 'create',
    'updateDoc': 'update',
    'deleteDoc': 'delete',
    'setDoc': 'set',
    'set': 'set',
    'update': 'update',
    'delete': 'delete',
  };
  final Map<String, Set<String>> pageWrites = {};
  final unresolved = <String>[];
  for (final f in Directory('admin_panel/src/pages').listSync().whereType<File>()) {
    if (!f.path.endsWith('.tsx')) continue;
    final name = f.uri.pathSegments.last.replaceAll('.tsx', '');
    // **التعليقاتُ تُحجَبُ أوّلاً.** شرحُ إصلاحٍ يَقتبسُ النداءَ الذي أزاله
    // (مثلاً «كان `deleteDoc(users/{id})` وحدَه») يُقرأُ كتابةً قائمةً،
    // فيُبلِّغُ الحارسُ عن هدفٍ لم يُعرَف — وهو فخُّ «الحارسُ يَسقطُ على
    // توثيقِه» في ثوبِ استخراجٍ. والمقابلةُ بالخامِّ بعدَه كي لا يُجوّفَه
    // الحجب.
    final raw = f.readAsStringSync();
    final src = raw
        .split('\n')
        .map((l) {
          final t = l.trimLeft();
          return (t.startsWith('//') || t.startsWith('/*') || t.startsWith('*'))
              ? ''
              : l;
        })
        .join('\n');

    // المراجعُ الوسيطة: `const ref = doc(db, 'orders', id)` ثم
    // `updateDoc(ref, …)`. بلا حلِّها تَخرجُ صفحةٌ كلُّ كتاباتِها عبر مرجعٍ من
    // دائرةِ الفحصِ **بصمت** — وهو شكلُ الحارسِ العقيم.
    final refColl = <String, String>{};
    for (final m in RegExp(r"(?:const|let)\s+(\w+)\s*=\s*doc\(\s*db\s*,\s*'([\w_]+)'")
        .allMatches(src)) {
      refColl[m.group(1)!] = m.group(2)!;
    }
    final hits = <String>{};
    // **الوسيطُ الأوّلُ بموازنةِ الأقواسِ لا بنمطٍ غيرِ طَمّاع.** أوّلُ صياغةٍ
    // كتبت `([\s\S]{0,80}?)[,)]` فتوقّفت عند أوّلِ فاصلةٍ — وهي الفاصلةُ
    // **داخلَ** `doc(db, 'orders', id)` — فصار الوسيطُ `doc(db` ولم يُعرَف
    // هدفُ أيِّ كتابة. (نفسُ فخِّ النمطِ غيرِ الطمّاعِ الذي أعقمَ حارسَ نصِّ
    // الاستثناءِ من قبل.)
    String firstArg(String s, int open) {
      var depth = 0;
      for (var i = open; i < s.length; i++) {
        final c = s[i];
        if (c == '(' || c == '[' || c == '{') depth++;
        if (c == ')' || c == ']' || c == '}') {
          depth--;
          if (depth == 0) return s.substring(open + 1, i);
        }
        if (c == ',' && depth == 1) return s.substring(open + 1, i);
      }
      return '';
    }

    for (final m in RegExp(
            r'(?:\b(addDoc|updateDoc|deleteDoc|setDoc)|'
            r'\b(?:tx|t|batch|transaction)\.(set|update|delete))\(')
        .allMatches(src)) {
      final verb = verbOf[m.group(1) ?? m.group(2)!]!;
      final arg = firstArg(src, m.end - 1);
      final direct =
          RegExp(r"(?:collection|doc)\(\s*db\s*,\s*'([\w_]+)'").firstMatch(arg);
      if (direct != null) {
        hits.add('$verb|${direct.group(1)}');
        continue;
      }
      final ident = RegExp(r'^\s*(\w+)\s*$').firstMatch(arg);
      if (ident != null && refColl.containsKey(ident.group(1))) {
        hits.add('$verb|${refColl[ident.group(1)]}');
        continue;
      }
      unresolved.add('$name: ${m.group(1)}(${arg.trim()}…)');
    }
    if (hits.isNotEmpty) pageWrites[name] = hits;
  }

  // ── (د) المسار → المُكوِّن، والمسار → الأدوار ─────────────────────────────
  final String app = read('admin_panel/src/App.tsx');
  final Map<String, String> routeComp = {'/': 'Dashboard'};
  for (final m in RegExp(
          r'''<Route path="[\w-]*" element=\{guard\('([^']+)',\s*<(\w+)''')
      .allMatches(app)) {
    routeComp[m.group(1)!] = m.group(2)!;
  }
  final String access = read('admin_panel/src/config/access.ts');
  final Map<String, Set<String>> pageRoles = {};
  for (final m in RegExp(r"'(/[\w-]*)':\s*\[([^\]]*)\]").allMatches(access)) {
    pageRoles[m.group(1)!] = m
        .group(2)!
        .split(',')
        .map((x) => x.trim().replaceAll("'", ''))
        .where((x) => x.isNotEmpty)
        .toSet();
  }

  // ── المخالفاتُ المُعلَنة: لكلٍّ سببُها، وكلُّها إخفاءٌ في الواجهة ───────────
  //
  // صيغةُ المفتاح: `المسار|الفعل|المجموعة` ← الأدوارُ التي تَرفضُها القواعد.
  const declared = <String, String>{
    // `Settings` تُخفي عن مدير الطلباتِ كلَّ تبويبٍ غيرِ «التغطية»
    // (`zonesOnly`)، فلا يَبلغُ زرَّ حفظِ الإعداداتِ أصلاً. قرارٌ قائمٌ موثَّقٌ
    // في `access.ts` نفسِه.
    '/settings|set|system_configs': 'orders_manager',
    // ويُكتَبُ `public_content` في نفسِ مُعالِجِ الحفظِ ذاك.
    '/settings|set|public_content': 'orders_manager',
    // `Contracts` صفحةٌ بثلاثِ مِلكيّات، وكلُّ تبويبٍ مُخفيٌّ عن الدورِ الذي
    // تَرفضُه القواعد: الباقتانِ عن مدير الطلبات، والعقودُ عن المسوّق.
    '/contracts|create|subscription_packages': 'orders_manager',
    '/contracts|update|subscription_packages': 'orders_manager',
    '/contracts|delete|subscription_packages': 'orders_manager',
    '/contracts|create|event_worker_packages': 'orders_manager',
    '/contracts|update|event_worker_packages': 'orders_manager',
    '/contracts|delete|event_worker_packages': 'orders_manager',
    '/contracts|update|contracts': 'marketing_admin',
    // والحذفُ `isSuperAdmin` وحدَه، فزرُّه مشروطٌ بـ`full` في الصفحة.
    '/contracts|delete|contracts': 'marketing_admin,orders_manager',
    // `Drivers` تَحذفُ `users/{uid}` **تراجعاً تعويضيّاً** داخلَ `catch` لا
    // زرّاً: لو فشلَ كتابةُ Firestore بعد إنشاءِ حسابِ Auth. فشلُ التراجعِ
    // مُبتلَعٌ عمداً (نمطُ `firebase_service.dart`) ولا يَراه أحد.
    '/drivers|delete|users': 'orders_manager',
  };

  group('خريطةُ الأدوارِ في اللوحةِ مقابلَ firestore.rules', () {
    test('الحجبُ لم يُفرِغ الفحصَ — الشرحُ ما زال يَذكرُ النداءَ المُزال', () {
    // المقابلةُ بالخامّ، لازمةٌ بعد كلِّ حجبٍ للتعليقات: `Admins` لم يَعُد
    // يَحذفُ المستندَ بنفسِه (صارَ `deleteStaffAccount`)، وشرحُ ذلك يَقتبسُ
    // النداءَ القديم — فلو لم يَبقَ الاقتباسُ لَما كان للحجبِ ما يَحجب،
    // ولَصارَ الفحصُ يَمرُّ على لا شيء.
    final raw = File('admin_panel/src/pages/Admins.tsx').readAsStringSync();
    expect(raw.contains('deleteDoc('), isTrue);
    expect(raw.contains("httpsCallable(functions, 'deleteStaffAccount')"), isTrue,
        reason: 'الحذفُ خادميٌّ — وإلّا عادت ثغرةُ رمزِ الإشعارات');
  });

  test('الاستخراجُ ليس فارغاً — حارسٌ عقيمٌ أسوأُ من غيابِه', () {
      expect(helpers.length, greaterThanOrEqualTo(5),
          reason: 'لم تُقرأ مُعيناتُ الأدوارِ من القواعد');
      expect(allRoles.length, equals(5), reason: 'isAdmin يَجمعُ الأدوارَ الخمسة');
      expect(colls.length, greaterThanOrEqualTo(20),
          reason: 'لم تُقرأ كتلُ المجموعاتِ من القواعد');
      expect(pageWrites.length, greaterThanOrEqualTo(10),
          reason: 'لم تُقرأ كتاباتُ صفحاتِ اللوحة');
      expect(pageRoles.length, greaterThanOrEqualTo(15),
          reason: 'لم تُقرأ خريطةُ الأدوار');
      expect(routeComp.length, greaterThanOrEqualTo(15),
          reason: 'لم تُقرأ مسارات App.tsx');
      // ولا كتابةً تَعذّرَ ردُّها إلى مجموعتِها: تجاهلُها صمتٌ، والصمتُ هو
      // ما يُنتجُ حارساً عقيماً.
      expect(unresolved, isEmpty,
          reason: 'كتاباتٌ لم يُعرَف هدفُها — وسِّعْ حلَّ المراجع:\n'
              '${unresolved.join("\n")}');
    });

    test('ولا دورَ يَرى صفحةً تَرفضُ القواعدُ أفعالَها — المجموعةُ كلُّها', () {
      final found = <String, String>{};
      for (final route in pageRoles.keys) {
        final comp = routeComp[route];
        final writes = pageWrites[comp] ?? <String>{};
        for (final w in writes) {
          final parts = w.split('|');
          final verb = parts[0];
          final coll = parts[1];
          final per = colls[coll];
          expect(per, isNotNull,
              reason: '$route ($comp) يَكتبُ $coll ولا كتلةَ قواعدَ له — '
                  'والقواعدُ تَمنعُ ما لا تَذكره');
          final allowed = <String>{
            ...(per!['write'] ?? <String>{}),
            if (verb == 'set') ...(per['create'] ?? <String>{}),
            if (verb == 'set') ...(per['update'] ?? <String>{}),
            if (verb != 'set') ...(per[verb] ?? <String>{}),
          };
          final bad = pageRoles[route]!.difference(allowed).toList()..sort();
          if (bad.isNotEmpty) found['$route|$verb|$coll'] = bad.join(',');
        }
      }
      // المقارنةُ على المجموعةِ كلِّها: مخالفةٌ جديدةٌ تَسقط، ومخالفةٌ أُصلحت
      // ولم تُحذَف من القائمةِ تَسقطُ كذلك فلا تَتعفّنُ القائمة.
      expect(found, equals(declared),
          reason: 'فروقٌ غيرُ مُعلَنة:\n'
              '  جديدةٌ: ${found.keys.toSet().difference(declared.keys.toSet())}\n'
              '  زائلةٌ من الشفرةِ وباقيةٌ في القائمة: '
              '${declared.keys.toSet().difference(found.keys.toSet())}');
    });

    test('وكلُّ مُعلَنةٍ إخفاءٌ فعليٌّ في الواجهةِ لا مجرَّدُ استثناء', () {
      final settings = read('admin_panel/src/pages/Settings.tsx');
      expect(settings, contains("const zonesOnly = role === 'orders_manager'"));
      expect(settings, contains("allTabs.filter(t => t.id === 'coverage')"));

      final contracts = read('admin_panel/src/pages/Contracts.tsx');
      expect(contracts, contains("const canPackages = full || role === 'marketing_admin'"));
      expect(contracts, contains("const canContracts = full || role === 'orders_manager'"));
      expect(contracts, contains('{canPackages && activeTab'));
      expect(contracts, contains('{canContracts && activeTab'));
      // وزرُّ الحذفِ للمدير العامِّ وحدَه (شاشةُ Flutter مرجعُه).
      expect(contracts, contains('{full && <button'));
      expect(read('lib/screens/admin/admin_contracts_screen.dart'),
          contains('if (_canDeleteContracts)'),
          reason: 'شاشةُ Flutter هي المرجعُ — لو زال إخفاؤها فالقرارُ يُراجَع');
      // والصفحةُ تَستقبلُ الدورَ فعلاً، وإلّا فكلُّ ما سبقَ حبرٌ على ورق.
      expect(app, contains("guard('/contracts', <Contracts role={role} />)"));

      final drivers = read('admin_panel/src/pages/Drivers.tsx');
      expect(drivers, contains("try { await deleteDoc(doc(db, 'users', uid)); } catch"),
          reason: 'حذفُ users هنا تراجعٌ تعويضيٌّ داخلَ catch لا زرّ');
    });

    test('والادّعاءُ في رأسِ access.ts ما زال مكتوباً — هذا الفحصُ قارئُه', () {
      // الادّعاءُ يَنقسمُ على سطرَين في الرأس، فنُسوّي المسافاتِ وبادئةَ
      // التعليقِ قبلَ البحثِ — وإلّا فالفحصُ يَسقطُ على صياغةٍ لا على معنى.
      final claim = access
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\s*//\s?'), ''))
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(claim,
          contains('Kept in sync with firestore.rules and the Cloud '
              "Functions' _assertAdmin checks so a role never sees a page "
              'whose actions the backend would reject'),
          reason: 'إن زال الادّعاءُ فمَوضوعُ هذا الفحصِ يَحتاجُ مراجعة');
      // والتجريدُ أزالَ شيئاً فعلاً (نمطٌ معطوبٌ لو لم يُزِل).
      expect(rules.length, lessThan(rulesRaw.length));
      // والمضادّة: أسماءُ المُعيناتِ ما زالت في الخامّ بعد التجريد.
      expect(rulesRaw, contains('isSuperAdmin'));
    });
  });
  // ══════════════════════════════════════════════════════════════════════
  // والجهةُ الأخرى: بلاطاتُ `admin_more_screen` في تطبيقِ الإدارة.
  //
  // لكلِّ بلاطةٍ `'roles': [...]` يَدويّةٌ تَحكمُ مَن يَرى الشاشةَ — قائمةٌ
  // بلا قارئٍ كخريطةِ اللوحةِ تماماً. والتطبيقُ **سليمٌ** عليها اليوم (عشرون
  // بلاطةً، ثلاثةٌ وثلاثون فحصَ كتابة): المخالفتانِ الوحيدتانِ مُحجوبتانِ في
  // الواجهةِ بشرطِ دورٍ صريحٍ موثَّقٍ في الشفرة — وهو ما جعلَ اللوحةَ هي
  // الشاذّةَ لا القاعدةَ ولا التطبيق. فهذا الفحصُ يُبقيه كذلك.
  //
  // **وأوّلُ صياغةٍ لهذا الجزءِ كانت عقيمةً تماماً:** بحثت عن
  // `=> const XScreen(` بينما البلاطةُ تَكتبُ `'page': const XScreen(),` —
  // فصفرُ بلاطةٍ انحلَّ إلى شاشةٍ، و«صفرُ مخالفات» كان يَعني «صفرَ فحوص»،
  // وكِدتُ أُسجّلُها نتيجةً نظيفة. فأُضيفَ عدُّ الفحوصِ أدناه شرطاً.
  group('بلاطاتُ تطبيقِ الإدارةِ مقابلَ firestore.rules', () {
    final String more = read('lib/screens/admin/admin_more_screen.dart');

    final pairs = <List<Object>>[];
    for (final m in RegExp(r"'page':\s*(?:const\s+)?(\w+)\(").allMatches(more)) {
      final after = more.substring(
          m.end, (m.end + 400).clamp(0, more.length));
      final rm = RegExp(r"'roles':\s*\[([^\]]*)\]").firstMatch(after);
      pairs.add([
        m.group(1)!,
        rm == null
            ? <String>{}
            : rm
                .group(1)!
                .split(',')
                .map((x) => x.trim().replaceAll("'", ''))
                .where((x) => x.isNotEmpty)
                .toSet(),
      ]);
    }

    final cls2file = <String, String>{};
    for (final f in Directory('lib/screens/admin').listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(
              r'class (\w+) extends (?:StatelessWidget|StatefulWidget)')
          .allMatches(src)) {
        cls2file[m.group(1)!] = f.path;
      }
    }

    Set<String> writesOf(String path) {
      final src = File(path)
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final out = <String>{};
      for (final m in RegExp(
              r"collection\('([\w_]+)'\)[\s\S]{0,220}?\.(set|update|delete|add)\(")
          .allMatches(src)) {
        out.add('${m.group(2)}|${m.group(1)}');
      }
      return out;
    }

    const vmap = {
      'set': ['write', 'create', 'update'],
      'add': ['write', 'create'],
      'update': ['write', 'update'],
      'delete': ['write', 'delete'],
    };

    // المخالفتانِ المُعلَنتان، وكلتاهما حَجبٌ صريحٌ في الواجهة.
    const declaredTiles = <String, String>{
      // زرُّ الحذفِ النهائيِّ للعقدِ مشروطٌ بـ`_canDeleteContracts`.
      'AdminContractsScreen|delete|contracts': 'orders_manager',
      // وبندُ «الحذف النهائي» في قائمةِ المستخدمِ مشروطٌ بـ`_role == 'super_admin'`.
      'AdminUsersScreen|set|account_deletions': 'orders_manager',
    };

    test('كلُّ بلاطةٍ تَحلُّ إلى شاشةٍ وتُفحَصُ كتاباتُها فعلاً', () {
      expect(pairs.length, greaterThanOrEqualTo(18),
          reason: 'لم تُقرأ بلاطاتُ admin_more_screen');
      final unmapped = pairs
          .where((p) => !cls2file.containsKey(p[0] as String))
          .map((p) => p[0] as String)
          .toList();
      expect(unmapped, isEmpty, reason: 'شاشاتٌ لم تُربَط بملفّها: $unmapped');
      final noRoles = pairs
          .where((p) => (p[1] as Set<String>).isEmpty)
          .map((p) => p[0] as String)
          .toList();
      expect(noRoles, isEmpty, reason: "بلاطاتٌ بلا 'roles': $noRoles");
    });

    test('ولا بلاطةٌ تَمنحُ دوراً كتابةً تَرفضُها القواعدُ — المجموعةُ كلُّها',
        () {
      final found = <String, String>{};
      var checks = 0;
      for (final p in pairs) {
        final cls = p[0] as String;
        final roles = p[1] as Set<String>;
        final file = cls2file[cls];
        if (file == null) continue;
        for (final w in writesOf(file)) {
          final verb = w.split('|')[0];
          final coll = w.split('|')[1];
          checks++;
          final per = colls[coll];
          expect(per, isNotNull,
              reason: '$cls يَكتبُ $coll ولا كتلةَ قواعدَ له');
          final allowed = <String>{};
          for (final v in vmap[verb]!) {
            allowed.addAll(per![v] ?? <String>{});
          }
          // `super_admin` يُستثنى: البلاطاتُ تَكتبُه ولا تَكتبُ `admin`،
          // والقواعدُ تَعدُّهما سواءً — فمقارنتُه ضجيجٌ لا إشارة.
          final bad = (roles.difference(allowed)..remove('super_admin')).toList()
            ..sort();
          if (bad.isNotEmpty) found['$cls|$verb|$coll'] = bad.join(',');
        }
      }
      // **العدُّ شرطٌ**: أوّلُ صياغةٍ فحصت صفراً وقالت «صفرَ مخالفات».
      expect(checks, greaterThanOrEqualTo(25),
          reason: 'عددُ فحوصِ الكتابةِ انهار — الفحصُ عقيم');
      expect(found, equals(declaredTiles),
          reason: 'فروقٌ غيرُ مُعلَنة:\n'
              '  جديدةٌ: ${found.keys.toSet().difference(declaredTiles.keys.toSet())}\n'
              '  زائلةٌ: ${declaredTiles.keys.toSet().difference(found.keys.toSet())}');
    });

    test('والمُعلَنتانِ محجوبتانِ في الواجهةِ بشرطِ دورٍ صريح', () {
      final contracts = read('lib/screens/admin/admin_contracts_screen.dart');
      expect(contracts,
          contains("bool get _canDeleteContracts => const ['admin', 'super_admin']"));
      expect(contracts, contains('if (_canDeleteContracts)'));
      final users = read('lib/screens/admin/admin_users_screen.dart');
      expect(users, contains("if (_role == 'super_admin')"));
      expect(users, contains("collection('account_deletions')"));
    });
  });
}
