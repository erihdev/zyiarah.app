// ════════════════════════════════════════════════════════════════════════
// دورُ الموظّفِ: مصدرٌ واحدٌ، ومفتاحُ إيقافٍ له قارئ (2026-10-05)
//
// ثلاثةُ أعطالٍ من عائلةٍ واحدة — «سطحُ الإدارةِ يُخالِفُ ما يُنفّذُه الخادم»:
//
// (أ) `firebase_service.getUserRole` كان يَقرأُ `admins/{uid}` **أوّلاً**
//     ويُعيدُ `staff_role` منه، و`users` لا يُقرأُ إلّا إن غابَ مستندُ
//     `admins`. والقواعدُ تَقرأُ `users` وحدَه للأدوارِ الفرعيّة
//     (`getUserData()` = `get(/users/$uid).data`) — فسؤالٌ واحدٌ بمصدرَين.
//     وتعليقُ القواعدِ نفسِه يَقول «staff_role IS the effective role
//     (getUserRole trusts it first)» — صحيحٌ عن مُعيِّنِ القواعد، كاذبٌ عن
//     دالّةِ العميل. ادّعاءٌ بلا قارئ، سادسَ مرّةٍ في هذا المستودع.
//
// (ب) `_saveStaff` كان يَكتبُ `users` ثمّ `admins` بلا ذرّيّة: ففشلُ الثانيةِ
//     يُبقي القائمةَ (تَقرأُ `admins`) على الدورِ القديمِ والقواعدَ على
//     الجديد. **تنزيلٌ ⇒ يُرى بصلاحيّةٍ تَرفضُها القواعدُ في كلِّ كتابة.**
//
// (ج) ومفتاحُ «إيقافِ موظّف» كان يَكتبُ `admins/{id}.is_active` **ولا قارئَ
//     لذلك الحقلِ في المستودعِ كلِّه**: لا القواعدُ، ولا الدوالُّ، ولا
//     `getUserRole`. فمَن أوقفَه المالكُ يَدخلُ ويَعملُ بكلِّ ما يُجيزُه
//     دورُه والشاشةُ تَقولُ «معطّل» — مفتاحٌ يُستعملُ **بدلَ الحذف**.
//     (مُثبَتٌ على المُحاكي: بإزالةِ `staffEnabled()` تَنجحُ الأربعةُ.)
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _mask(String src) => src
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('///')) ? ' ' * l.length : l;
    })
    .join('\n');

/// جسمُ دالّةٍ بموازنةِ الأقواس — **وقائمةُ المعامَلاتِ تُوازَنُ أوّلاً.**
/// أخذُ أوّلِ `{` بعدَ الاسمِ يَلتقطُ قوسَ المعامَلاتِ المُسمّاةِ
/// (`{String? phone}`) لا الجسم، وهو فخُّ الحدِّ المسجَّلُ في هذا المستودعِ
/// ستَّ مرّاتٍ — وقعتُ فيه سابعةً وأسقطَ فحصَين.
String _body(String src, String signature) {
  final i = src.indexOf(signature);
  if (i < 0) throw StateError('التوقيعُ اختفى: $signature');
  final lp = src.indexOf('(', i);
  var open = -1;
  if (lp >= 0) {
    var d = 0;
    for (var k = lp; k < src.length; k++) {
      if (src[k] == '(') d++;
      if (src[k] == ')') {
        d--;
        if (d == 0) {
          open = src.indexOf('{', k);
          break;
        }
      }
    }
  } else {
    open = src.indexOf('{', i + signature.length - 1);
  }
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
  final svcRaw = File('lib/services/firebase_service.dart').readAsStringSync();
  final svc = _mask(svcRaw);
  final mgrRaw =
      File('lib/screens/admin/admin_managers_screen.dart').readAsStringSync();
  final mgr = _mask(mgrRaw);
  final rulesRaw = File('firestore.rules').readAsStringSync();
  final rules = _mask(rulesRaw);
  final ruleHelper = File('lib/utils/staff_role.dart').readAsStringSync();

  group('(أ) المصدرُ واحدٌ: `users` كما تَقرأُ القواعد', () {
    test('getUserRole يَقرأُ users قبلَ admins', () {
      final b = _body(svc, 'Future<String?> getUserRole(String uid');
      final iUsers = b.indexOf("collection('users')");
      final iAdmins = b.indexOf("collection('admins')");
      expect(iUsers, greaterThan(-1), reason: 'لا قراءةَ لـusers إطلاقاً');
      expect(iAdmins, greaterThan(-1),
          reason: 'احتياطُ admins زال — وهو لحسابِ تأسيسٍ بلا دورٍ في users');
      expect(iUsers, lessThan(iAdmins),
          reason: 'admins ما زال أوّلاً — فالواجهةُ تُخالِفُ القواعد');
    });

    test('ويُنادي القاعدةَ المشتركةَ ولا يُعيدُ تعدادَ الأسبقيّةِ بجوارِها',
        () {
      final b = _body(svc, 'Future<String?> getUserRole(String uid');
      expect(b.contains('roleFromUsersDoc('), isTrue);
      expect(b.contains('roleFromAdminsDoc('), isTrue);
      expect(b.contains('staffAccountDisabled('), isTrue,
          reason: 'مفتاحُ الإيقافِ لا يُقرأُ في العميل');
      // نسخةٌ إنلاين من الأسبقيّةِ هي ما يَنحرِف.
      expect(RegExp(r"\['staff_role'\]\s*\?\?").hasMatch(b), isFalse,
          reason: 'عادت الأسبقيّةُ مكتوبةً بيدٍ داخلَ getUserRole');
    });

    test('والقاعدةُ تَقرأُ الإيقافَ من users لا من admins', () {
      // قراءتُه من `admins` تَعني مستنداً ثانياً في كلِّ دخول، و`users` هو
      // المُحمَّلُ أصلاً في `getUserData()` على جهةِ القواعد.
      final b = _body(ruleHelper, 'bool staffAccountDisabled(');
      expect(b.contains("'is_active'"), isTrue);
      expect(b.contains('admins'), isFalse,
          reason: 'الإيقافُ يُقرأُ من admins — قراءةٌ ثانيةٌ ومصدرٌ ثانٍ');
      // الغيابُ = مُفعَّل: اعتبارُه إيقافاً يُقفِلُ الإدارةَ كلَّها.
      expect(b.contains('== false'), isTrue,
          reason: 'الشرطُ ليس «== false» — فالغيابُ قد يُقرأُ إيقافاً');
    });
  });

  group('(ب)+(ج) الكتاباتُ ذرّيّةٌ على الزوجِ معاً', () {
    test('_saveStaff دفعةٌ واحدةٌ تَكتبُ users و admins', () {
      final b = _body(mgr, 'Future<void> _saveStaff() async ');
      expect(b.contains('batch.commit()'), isTrue, reason: 'ليست دفعة');
      expect(RegExp(r'batch\.set\(').allMatches(b).length, 2,
          reason: 'كتاباتُ الدفعةِ ليست اثنتَين (users + admins)');
      expect(b.contains("collection('users')"), isTrue);
      expect(b.contains("collection('admins')"), isTrue);
      expect(RegExp(r"collection\('(users|admins)'\)\.doc\([^)]*\)\.set\(")
          .hasMatch(b), isFalse,
          reason: 'كتابةٌ مباشرةٌ خارجَ الدفعةِ عادت');
    });

    test('ومفتاحُ الإيقافِ يَكتبُ المستندَين دفعةً', () {
      // المِفتاحُ في جسمِ `build` لا في دالّةٍ مُسمّاة، فالنطاقُ هو الملفُّ
      // مع تثبيتِ شكلِ الكتابةِ بعينِه.
      expect(mgr.contains("tb.update(") && mgr.contains("tb.set("), isTrue,
          reason: 'الإيقافُ ليس دفعةً — فالعرضُ قد يَفترِقُ عن الإنفاذ');
      expect(mgr.contains('tb.commit()'), isTrue);
      expect(
          RegExp(r"collection\('admins'\)\.doc\(doc\.id\)\.update\(")
              .hasMatch(mgr),
          isFalse,
          reason: 'عادت كتابةُ admins وحدَها — وهي الحالةُ بلا قارئ');
    });
  });

  group('القواعدُ تُنفِّذُ الإيقافَ على كلِّ مُعيِّنِ موظّف', () {
    /// مجموعةُ مُعيِّناتِ الموظّفينَ **مُشتَقّةٌ** من الملفِّ لا مكتوبةً
    /// بيد: مُعيِّنٌ سادسٌ يُضافُ غداً يَدخلُ النطاقَ بنفسِه، وهو تصحيحُ
    /// «حارسٌ ضيّقٌ وقاعدةٌ عامّة» قبلَ أن يَضيق.
    Map<String, String> staffHelpers() {
      final out = <String, String>{};
      for (final m in RegExp(r'function (is[A-Za-z]*(?:Admin|Manager))\(\)')
          .allMatches(rules)) {
        final name = m.group(1)!;
        final body = _body(rules, 'function $name()');
        // مُعيِّنُ موظّفٍ هو ما يُقارِنُ الدورَ بقائمةٍ فيها super_admin،
        // أو يَختبرُ وجودَ مستندِ `admins`.
        if (body.contains("'super_admin'") || body.contains('admins/')) {
          out[name] = body;
        }
      }
      return out;
    }

    test('الاشتقاقُ وجدَ المُعيِّناتِ فعلاً — فلا فحصَ على فراغ', () {
      final h = staffHelpers();
      expect(h.length, greaterThanOrEqualTo(5),
          reason: 'مُعيِّناتُ الموظّفينَ لم تُقرأ: ${h.keys}');
      for (final n in [
        'isAdmin',
        'isOrdersManager',
        'isAccountantAdmin',
        'isMarketingAdmin',
        'isSuperAdmin',
      ]) {
        expect(h.containsKey(n), isTrue, reason: '$n خارجَ الاشتقاق');
      }
    });

    test('وكلُّ واحدٍ منها يَحملُ staffEnabled()', () {
      staffHelpers().forEach((name, body) {
        expect(body.contains('staffEnabled()'), isTrue,
            reason: '$name بلا بوّابةِ الإيقاف — فموقوفٌ يَعملُ عبرَه');
      });
    });

    test('والبوّابةُ تَقرأُ users ولا تُضيفُ قراءةً ثانية', () {
      final b = _body(rules, 'function staffEnabled()');
      expect(b.contains('getUserData()'), isTrue,
          reason: 'لا تَقرأُ مستندَ users المُحمَّلَ أصلاً');
      expect(b.contains('is_active'), isTrue);
      expect(b.contains('get(/databases'), isFalse,
          reason: 'قراءةٌ ثانيةٌ في كلِّ تقييمِ قاعدة');
      // ومحصورٌ بمُعيِّناتِ الموظّفين: إدخالُه في getUserRole() نفسِها
      // كان سيَطرُدُ عميلاتٍ بحقلٍ كُتبَ لسببٍ آخر.
      expect(_body(rules, 'function getUserRole()').contains('is_active'),
          isFalse,
          reason: 'البوّابةُ دخلت getUserRole فصارت تَمَسُّ العملاءَ والسائقين');
    });
  });

  group('المضادّات: المحجوبُ تعليقٌ لا شفرةٌ أُزيلت', () {
    test('الشكلُ القديمُ ما زال موثَّقاً في الخامّ', () {
      expect(svcRaw.contains('كان هذا الترتيبُ مقلوباً'), isTrue,
          reason: 'شرحُ الأسبقيّةِ القديمةِ زال');
      expect(mgrRaw.contains('ولا قارئَ لذلك الحقلِ'), isTrue,
          reason: 'شرحُ المفتاحِ بلا قارئٍ زال');
      expect(rulesRaw.contains('STAGE-C'), isTrue,
          reason: 'حجزُ النشرِ لم يُعلَن');
    });
  });
}
