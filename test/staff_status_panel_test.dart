// ════════════════════════════════════════════════════════════════════════
// حالةُ حسابِ الموظّفِ في لوحةِ الويبِ — ثلاثةُ أعلامٍ تُعطّلُ، وصفرٌ كان
// يُقرَأ (2026-10-05)
//
// `Admins.tsx` كان يَرسمُ عمودَ الحالةِ من `admin.status !== 'inactive'`،
// و**لا شيءَ في المستودعِ كلِّه يَكتبُ `status: 'inactive'` على مستندِ
// مستخدم** — الكاتبُ الوحيدُ لتلك القيمةِ هو محرِّرُ الكوبونات، على مجموعةٍ
// أخرى. فالعمودُ كان «نشط» بعلامةٍ خضراءَ **أبداً**، في كلِّ مسارِ تعطيلٍ
// موجود: `is_active == false` (مفتاحُ تطبيقِ الإدارة، وما تَقرؤه
// `staffEnabled()` في القواعدِ و`getUserRole`)، و`status == 'banned'`
// (تَكتبُه **هذه اللوحةُ نفسُها** من صفحةِ المستخدمين — قائمتُها بلا
// مُرشِّحِ دور)، و`is_blocked == true`. فاللوحةُ تَحظُرُ حساباً في صفحةٍ
// وتَقولُ عنه «نشط» في أخرى.
//
// وهي قصّةُ `driverActivation.ts` بعينِها — شارةٌ تَقرأُ حقلاً والكاتبُ
// يَكتبُ غيرَه — على المجموعةِ التي لم تَنَلْ ذلك الإصلاح. فنطاقُ هذا
// الحارسِ **مُشتَقٌّ**: الأعلامُ تُقرأُ من القواعدِ ومن `user_provider`
// وتُقابَلُ بما تُعلِنُه الوحدةُ، فعلَمُ تعطيلٍ رابعٌ يُضافُ هناك يَسقطُ
// الفحصَ بدلَ أن يَغيبَ عن الجدولِ سنةً.
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// يَحجبُ أسطرَ التعليقِ بمسافاتٍ بطولِها فتَبقى الإزاحاتُ مطابقةً.
String _mask(String src) => src
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*'))
          ? ' ' * l.length
          : l;
    })
    .join('\n');

/// جسمُ دالّةٍ بموازنةِ الأقواس — لا `indexOf('}')`، وهو الفخُّ الذي أوقعَ
/// حُرّاساً في هذا المستودعِ سبعَ مرّات.
String _braced(String src, String signature) {
  final i = src.indexOf(signature);
  if (i < 0) throw StateError('التوقيعُ اختفى: $signature');
  final open = src.indexOf('{', i + signature.length - 1);
  if (open < 0) throw StateError('لا جسمَ لـ$signature');
  var depth = 0;
  for (var j = open; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, j + 1);
    }
  }
  throw StateError('قوسٌ غيرُ مُغلَقٍ في $signature');
}

void main() {
  final rulesRaw = File('firestore.rules').readAsStringSync();
  final rules = _mask(rulesRaw);
  final providerRaw = File('lib/providers/user_provider.dart').readAsStringSync();
  final blockRaw =
      File('lib/utils/account_block.dart').readAsStringSync();
  final block = _mask(blockRaw);
  final provider = _mask(providerRaw);
  final utilRaw = File('admin_panel/src/utils/staffStatus.ts').readAsStringSync();
  final util = _mask(utilRaw);
  final adminsRaw = File('admin_panel/src/pages/Admins.tsx').readAsStringSync();
  final admins = _mask(adminsRaw);
  final usersRaw = File('admin_panel/src/pages/Users.tsx').readAsStringSync();
  final users = _mask(usersRaw);
  final managersRaw =
      File('lib/screens/admin/admin_managers_screen.dart').readAsStringSync();
  final managers = _mask(managersRaw);

  /// الأعلامُ **مُشتَقّةٌ** من القارئَين الآمِرَين: القواعدُ (إنفاذُ الكتابة)
  /// و`user_provider` (الخروجُ القسريّ). قائمةٌ مكتوبةٌ بيدٍ هنا كانت
  /// ستَتخلّفُ عن علَمٍ رابعٍ بصمت.
  Set<String> derivedFlags() {
    final out = <String>{};
    // (١) القواعد: `getUserData().get('is_active', true) != false`
    final gate = _braced(rules, 'function staffEnabled()');
    for (final m in RegExp(r"\.get\('([a-z_]+)'").allMatches(gate)) {
      out.add(m.group(1)!);
    }
    // (٢) قاعدةُ الحظر — **من موضعِها** لا من نسخةٍ: كانت مكتوبةً إنلاين في
    //     `user_provider` فكان الاشتقاقُ يَقرؤها هناك؛ وانتقلت إلى
    //     `utils/account_block.dart` (موضعٌ واحدٌ لمُنفِّذٍ وشارةٍ)، فالاشتقاقُ
    //     يَقرأُ الأصلَ الآن — وفحصٌ أدناه يُثبِتُ أنّ المُنفِّذَ ما زال
    //     يُنادِيه، وإلّا كان الاشتقاقُ عن قاعدةٍ لا تُطبَّق.
    final ban = _braced(block, 'bool accountIsBlocked(');
    for (final m in RegExp(r"data\['([a-z_]+)'\]").allMatches(ban)) {
      out.add(m.group(1)!);
    }
    return out;
  }

  Set<String> declaredFlags() {
    final m = RegExp(r'STAFF_DISABLE_FIELDS\s*=\s*\[([^\]]*)\]').firstMatch(util);
    if (m == null) throw StateError('STAFF_DISABLE_FIELDS اختفت');
    return RegExp(r"'([a-z_]+)'")
        .allMatches(m.group(1)!)
        .map((x) => x.group(1)!)
        .toSet();
  }

  group('قاعدةُ حالةِ الموظّفِ مُشتَقّةٌ لا مكتوبةً بيد', () {
    test('(أ) الاشتقاقُ أصابَ القارئَين — فلا فحصَ على فراغ', () {
      final d = derivedFlags();
      expect(d.length, greaterThanOrEqualTo(3),
          reason: 'الاشتقاقُ انحلَّ إلى $d — حارسٌ أجوفُ أسوأُ من لا حارس');
      expect(d.contains('is_active'), isTrue, reason: 'القواعدُ لم تُقرَأ');
      expect(d.contains('status'), isTrue,
          reason: 'قاعدةُ الحظرِ في account_block.dart لم تُقرَأ');
      // والقاعدةُ المُشتَقّةُ هي المُطبَّقةُ فعلاً: المزوّدُ هو مَن يَطردُ.
      expect(provider.contains('accountIsBlocked('), isTrue,
          reason: 'user_provider لم يَعُدْ يُنادي قاعدةَ الحظر — '
              'فالاشتقاقُ عن قاعدةٍ لا تُطبَّق');
    });

    test('(ب) ما تُعلِنُه الوحدةُ = ما يَقرؤه الخادمُ والتطبيقُ، مجموعةً', () {
      expect(declaredFlags(), derivedFlags(),
          reason: 'علَمُ تعطيلٍ يَعرفُه الإنفاذُ ولا تَقرؤه اللوحةُ — أو عكسُه');
    });

    test('(ج) الوحدةُ تَقرأُ كلَّ علَمٍ فعلاً، لا تُعلِنُه فحسب', () {
      final body = _braced(util, 'export function staffState(');
      for (final f in derivedFlags()) {
        expect(body.contains(f), isTrue,
            reason: '`$f` مُعلَنٌ ولا يُقرَأُ في القاعدة — اسمٌ لا قدرة');
      }
      expect(body.contains("'banned'"), isTrue,
          reason: 'قيمةُ الحظرِ لا تُقارَن');
    });
  });

  group('الجدولُ يَقرأُ القاعدةَ ولا يُعيدُ تعدادَها', () {
    test('(د) الشارةُ تُنادي `staffState` وتُستورَد', () {
      expect(admins.contains("from '../utils/staffStatus.ts'"), isTrue,
          reason: 'الوحدةُ غيرُ مستورَدة');
      expect(RegExp(r'staffState\(admin\)').hasMatch(admins), isTrue,
          reason: 'الشارةُ لا تُنادي القاعدة');
      expect(admins.contains('موقوف'), isTrue, reason: 'حالةُ الوقفِ لا تُعرَض');
      expect(admins.contains('محظور'), isTrue, reason: 'حالةُ الحظرِ لا تُعرَض');
    });

    test("(هـ) `'inactive'` لم تَعُد قراراً في الجدول", () {
      // القيمةُ لا كاتبَ لها، فقراءتُها **هي** العطل.
      expect(admins.contains('inactive'), isFalse,
          reason: 'عادَ قرارٌ على قيمةٍ لا يَكتبُها شيءٌ — «نشط» أبداً');
    });

    test('(و) المضادّة: سببُ المنعِ ما زال موثَّقاً في الخامّ', () {
      // حجبُ التعليقاتِ هو ما يُجعلُ (هـ) ممكناً، فيَلزمُ إثباتُ أنّ
      // المحجوبَ شرحٌ لا شفرةٌ أُزيلت — الفخُّ الذي أوقعَ حُرّاساً هنا
      // اثنتَي عشرةَ مرّة.
      expect(utilRaw.contains("status: 'inactive'"), isTrue,
          reason: 'شرحُ العطلِ زال — فلا يَعرفُ قارئٌ ما يَحرُسُه هذا');
    });
  });

  group('الكُتّابُ الذين تَقرأُ القاعدةُ لهم ما زالوا قائمِين', () {
    test('(ز) صفحةُ المستخدمينَ ما زالت تَكتبُ `status: banned` — وبلا مُرشِّحِ دور', () {
      expect(RegExp(r"status:\s*banning \? 'banned'").hasMatch(users), isTrue,
          reason: 'كاتبُ الحظرِ تغيّرَ — فتعليلُ قراءةِ `status` يُراجَع');
      // لا `where('role', ...)` على قائمةِ المستخدمين: صفوفُ الموظّفينَ فيها،
      // وهو سببُ أنّ حظرَ موظّفٍ من هذه اللوحةِ مسارٌ قائمٌ لا نظريّ.
      expect(RegExp(r"collection\(db, 'users'\)\), where\(").hasMatch(users), isFalse,
          reason: 'صارت القائمةُ مُرشَّحةً بدورٍ — فيُراجَعُ التعليلُ لا يُسكَت');
    });

    test('(ح) مفتاحُ تطبيقِ الإدارةِ ما زال يَكتبُ `is_active` في المستندَين دفعةً', () {
      expect(managers.contains("'is_active': val"), isTrue,
          reason: 'كاتبُ الوقفِ تغيّرَ');
      expect(RegExp(r"tb\.update\(\s*_db\.collection\('admins'\)").hasMatch(managers),
          isTrue);
      expect(RegExp(r"tb\.set\(\s*_db\.collection\('users'\)").hasMatch(managers),
          isTrue,
          reason: 'الوقفُ لم يَعُد يَبلغُ `users` — وهو ما تَقرؤه القواعد');
    });

    test('(ط) القواعدُ ما زالت تُنفِّذُ الوقفَ — فالشارةُ مرآةٌ لا تخمين', () {
      expect(rules.contains('staffEnabled()'), isTrue);
      expect(RegExp(r'isOrdersManager\(\) \{\s*return isLoggedIn\(\) && staffEnabled\(\)')
              .hasMatch(rules),
          isTrue,
          reason: 'الوقفُ لم يَعُد يَمنعُ مديرَ الطلبات');
    });
  });

  group('البوّابةُ لا الشارةُ وحدَها — الدخولُ والإطار', () {
    final loginRaw = File('admin_panel/src/pages/Login.tsx').readAsStringSync();
    final login = _mask(loginRaw);
    final appRaw = File('admin_panel/src/App.tsx').readAsStringSync();
    final app = _mask(appRaw);

    test('(ي) الدخول: البوّابةُ بعدَ فحصِ الدورِ وقبلَ الانتقال', () {
      // العطلُ أخطرُ من الشارة: الحسابُ **الموقوفُ أو المحظورُ** كان يَدخلُ
      // اللوحةَ ويَعملُ، بينما تطبيقُ الإدارةِ يَرفضُه (`getUserRole` تُعيدُ
      // `null`) وتطبيقُ العميلةِ يُسجّلُ خروجَه فوراً — وبوّابةُ القواعدِ
      // (`staffEnabled()`) محجوزةٌ مع STAGE-C ولم تُنشَر.
      expect(login.contains("from '../utils/staffStatus.ts'"), isTrue,
          reason: 'القاعدةُ غيرُ مستورَدةٍ في صفحةِ الدخول');
      final iRole = login.indexOf('ADMIN_ROLES.includes(effRole)');
      final iGate = login.indexOf('staffState(ud)');
      final iNav = login.indexOf("navigate('/')");
      expect(iRole, greaterThan(0));
      expect(iGate, greaterThan(iRole),
          reason: 'البوّابةُ قبلَ معرفةِ الدورِ — فتُطبَّقُ على عميلة');
      expect(iNav, greaterThan(iGate),
          reason: 'الانتقالُ قبلَ البوّابةِ لا يَمنعُ شيئاً');
      expect(login.indexOf('signOut(auth)', iGate), greaterThan(iGate),
          reason: 'الجلسةُ تَبقى مفتوحةً بعدَ الرفض');
    });

    test('(ك) ورسالتانِ تُسمّيانِ السبب — لا ارتدادٌ صامت', () {
      // ارتدادٌ صامتٌ يُقرأُ «كلمةُ مرورٍ خاطئة» فيُعيدُ المحاولةَ
      // ويُراسِلُ الدعمَ — وهو ما يُحوّلُ إجراءً إداريّاً إلى عطلٍ مُبلَّغ.
      expect(login.contains('محظور'), isTrue, reason: 'حالةُ الحظرِ بلا نصّ');
      expect(login.contains('موقوف'), isTrue, reason: 'حالةُ الوقفِ بلا نصّ');
    });

    test('(ل) الإطار: `isAdmin` مقرونٌ بالقاعدة', () {
      expect(app.contains("from './utils/staffStatus.ts'"), isTrue);
      // والاقترانُ **ترتيباً** لا حضوراً: `staffIsActive` في الملفِّ لا
      // تَكفي، فقد تَكونُ في مُستمِعٍ آخرَ بينما المنحُ بالدورِ وحدَه.
      final iGrant = app.indexOf('setIsAdmin(staffRole &&');
      expect(iGrant, greaterThan(0),
          reason: 'الإطارُ يُمنَحُ بالدورِ وحدَه — فالموقوفُ يَحتفظُ به');
      final grant = app.substring(iGrant, iGrant + 160);
      expect(grant.contains('staffIsActive('), isTrue,
          reason: 'المنحُ غيرُ مقرونٍ بالقاعدة');
    });

    test('(م) وسحبُ الصلاحيةِ حيٌّ — لا عند الإقلاعِ وحدَه', () {
      // تطبيقُ العميلةِ يُسجّلُ خروجَ المحظورِ **لحظةَ** الحظر؛ وقراءةٌ
      // واحدةٌ عند تغيّرِ حالةِ المصادقةِ تَترُكُ جلسةً مفتوحةً عاملةً.
      final iSub = app.indexOf('unsubDoc = onSnapshot(');
      expect(iSub, greaterThan(0), reason: 'لا مُراقَبةَ حيّةً لمستندِه');
      final body = app.substring(iSub, iSub + 700);
      expect(body.contains('!snap2.exists() || !staffIsActive('), isTrue,
          reason: 'المُراقَبةُ لا تَقرأُ القاعدةَ (أو تَتجاهلُ مستنداً زال)');
      expect(body.contains('signOut(auth)'), isTrue,
          reason: 'المُراقَبةُ تَرى ولا تَفعل');
      // ومقصورةٌ على دورِ موظّف، كـ`staffAccountDisabled` في الدارت.
      expect(app.contains('if (staffRole) unsubDoc = onSnapshot('), isTrue,
          reason: 'المُراقَبةُ تَشملُ غيرَ الموظّفين — `is_active` على مستندِ '
              'عميلةٍ كُتبَ لسببٍ آخر');
      // وتُفَكُّ عند تغيّرِ المستخدمِ وعند التفكيك.
      expect(app.contains('unsubDoc?.();'), isTrue,
          reason: 'مُستمِعٌ لا يُفَكُّ يَتراكمُ على كلِّ تغيّرِ جلسة');
    });

    test('(ن) وخطأُ المُراقَبةِ صامتٌ **بسببٍ مكتوب**', () {
      // فشلُ قراءةٍ عابرٌ لا يَجوزُ أن يُخرِجَ المالكَ من لوحتِه؛ والقرارُ
      // الأوّلُ أُخِذ من `getDoc`. وهذا هو الاستثناءُ الوحيدُ المسموحُ هنا،
      // فيَلزمُ أن يَبقى سببُه في الخامّ.
      expect(appRaw.contains('صامتٌ عن قصد'), isTrue,
          reason: 'سببُ الصمتِ زال — فيُقرأُ سهواً');
    });
  });
}
