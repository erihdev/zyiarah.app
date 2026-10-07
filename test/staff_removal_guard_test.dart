import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **حذفُ موظّفٍ كان ثلاثةَ مساراتٍ ولا واحدٌ منها كاملاً.**
///
/// `fcm_tokens/{uid}` يَحملُ **نسخةً** من `role` و`staff_role`، وتوجيهُ البثِّ
/// وتنبيهاتِ `ADMIN_BROADCAST` يَستعلمُ عليها. وكاتبُ تلك النسخةِ واحدٌ: تطبيقُ
/// المستخدمِ عند الإقلاع أو الدخول أو تدويرِ الرمز. فإقصاءُ موظّفٍ كان يَحذفُ
/// مستندَين (أو واحداً من اللوحة) ويَترك:
///
///   * **حسابَ Auth حيّاً** — فيَستطيعُ الدخول.
///   * **رمزَ الإشعاراتِ موسوماً `role: 'admin'`** — فكلُّ تنبيهٍ إداريٍّ
///     (رقمُ طلب، مبلغ، اسمُ عميلة، فشلُ استرداد، عدمُ تطابقِ سعر) يَصِلُ
///     هاتفَه. **ولا يُصحَّحُ أبداً**: القواعدُ تَشترطُ أن يُطابقَ دورُ الرمزِ
///     `users/{id}`، وقراءةُ مستندٍ غائبٍ تَرفضُ الكتابة.
///
/// ومسارُ السائقِ (`deleteDriverAccount`) كان يَفعلُ الأربعةَ كاملةً منذ
/// البداية، وتعليقُه يُسمّي تنظيفَ الرمزِ بالاسم — فالقاعدةُ مُنفَّذةٌ في
/// واحدٍ من ثلاثة، شكلُ `isAssignableDriver` بعينِه.
String _read(String p) => File(p).readAsStringSync();

String _code(String src) => src
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('/*') || t.startsWith('*'))
          ? ''
          : l;
    })
    .join('\n');

/// جسمُ صادرٍ من `index.js` حتى الصادرِ الذي يَليه.
String _export(String idx, String name) =>
    _decl(idx, 'exports.$name = ');

/// جسمُ إعلانٍ عُلويٍّ بحدِّه الحقيقيّ — أوّلُ إعلانٍ بعدَه.
///
/// كان `_assertSuperAdmin` يُقتطَعُ بـ`substring(at, at + 900)` وطولُه ٧٦٢
/// حرفاً، أي ١٣٨ حرفاً من التاليةِ له داخلَ الشريحة: فحصٌ يَقرأُ دالّةً
/// أخرى ويَحكمُ بها. والحارسُ هنا يَملكُ الاقتطاعَ البنيويَّ سلفاً
/// (`_export`) ولم يُستعمَل — فعُمِّمَ ليَشملَ الدوالَّ غيرَ المُصدَّرة.
String _decl(String idx, String anchor) {
  final i = idx.indexOf(anchor);
  expect(i, greaterThan(-1), reason: '«$anchor» اختفى');
  final next = RegExp(r'^(exports\.\w+ = |async function |function )',
          multiLine: true)
      .allMatches(idx)
      .map((m) => m.start)
      .firstWhere((p) => p > i, orElse: () => idx.length);
  expect(next - i, greaterThan(200), reason: 'اقتطاعُ «$anchor» انهار');
  return idx.substring(i, next);
}

void main() {
  final idx = _read('functions/index.js');
  final code = _code(idx);

  group('إقصاءُ موظّفٍ يُقصيه من كلِّ مكان', () {
    test('(أ) الحذفُ خادميٌّ ويُسقِطُ الأربعةَ: Auth والمستندان والرمز', () {
      final b = _code(_export(idx, 'deleteStaffAccount'));
      expect(b, contains('getAuth().deleteUser(staffId)'));
      for (final col in ['admins', 'users', 'fcm_tokens', 'fcm_token']) {
        expect(b, contains('collection("$col").doc(staffId)'), reason: col);
      }
      // تسامحٌ مع موظّفٍ قديمٍ بلا حسابِ Auth — نفسُ قرارِ مسارِ السائق.
      expect(b, contains('auth/user-not-found'));
    });

    test('(ب) للمدير العامِّ وحدَه — لا `_assertAdmin` الأوسع', () {
      final b = _code(_export(idx, 'deleteStaffAccount'));
      expect(b, contains('_assertSuperAdmin(request)'));
      expect(b.contains('_assertAdmin(request)'), isFalse,
          reason: 'القواعدُ تَحصرُ الكتابةَ على `admins` بـisSuperAdmin()، '
              'و_assertAdmin يُجيزُ orders_manager — أوسعَ من القواعد');
      // والمُعيِّنُ يَقرأُ الدورَ كما تَقرؤه القواعدُ: staff_role ثمّ role.
      final body = _code(_decl(idx, 'async function _assertSuperAdmin'));
      expect(body, contains('data.staff_role || data.role'));
      expect(body, contains('["admin", "super_admin"]'));
    });

    test('(ج) لا يَحذفُ نفسَه — نظيرُ «لديه طلبات نشطة» في مسارِ السائق', () {
      final b = _code(_export(idx, 'deleteStaffAccount'));
      expect(b, contains('staffId === actorUid'));
      expect(b, contains('failed-precondition'));
    });

    test('(د) المُشغّلُ هو ما يُغني عن تذكّرِ كلِّ مسار', () {
      final b = _code(_export(idx, 'syncRoleToPushToken'));
      expect(_code(idx), contains('exports.syncRoleToPushToken = onDocumentWritten'));
      expect(b, contains('document: "users/{uid}"'));
      // زوالُ المستخدمِ ⇒ حذفُ الرمز (الشاشةُ واللوحةُ والكونسولُ جميعاً).
      expect(b, contains('tokRef.delete()'));
      // وتغيُّرُ الدورِ ⇒ تحديثُ النسخةِ، فلا تَبقى بائتةً بعد ترقيةٍ أو
      // تنزيل. **المقارنةُ نفسُها مثبَّتةٌ لا اسمُها**: صياغةٌ أولى طلبَت
      // حضورَ المعرّفِ فحسب، فمرَّ اختبارُ قضمٍ جعلَه `= false` أخضرَ —
      // وهو درسُ «الاسمُ ليس القدرة» واقعاً على حارسٍ كتبتُه الآن.
      expect(b, contains('(before.role || null) !== (after.role || null)'));
      expect(b,
          contains('(before.staff_role || null) !== (after.staff_role || null)'));
      expect(b, contains('if (!roleChanged && !staffChanged) return null;'));
      // **وُسِمَ الحِمْلُ باسمِه لا بحقولِه (2026-10-05).** كان الفحصُ يَشدُّ
      // النصَّ `role_synced_at` داخلَ جسمِ المُشغّل، فحين اُستُخرِجَ الحِمْلُ
      // إلى `_tokenRolePayload` — لأنّ مكنسةَ الانحرافِ تَكتبُ الشكلَ نفسَه
      // وكانت نسخةً ثانيةً — سقطَ الفحصُ **بالنقلِ لا بالانحراف**، وهو نمطٌ
      // مسجَّلٌ في هذا المستودع. فالشدُّ الآن إلى النداءِ **وإلى الحِمْلِ في
      // موضعِه الواحد**: أشدُّ من النصِّ الذي كان، لأنّ نسخةً إنلاين ثانيةً
      // تُسقطُه أيضاً.
      expect(b, contains('_tokenRolePayload('),
          reason: 'المُشغّلُ لا يَكتبُ حِمْلَ الوسمِ المشترَك');
      final int pi = idx.indexOf('function _tokenRolePayload(');
      expect(pi, greaterThan(0), reason: 'موضعُ الحِمْلِ الواحدُ اختفى');
      expect(idx.substring(pi, pi + 400), contains('role_synced_at'),
          reason: 'حِمْلُ الوسمِ لا يَكتبُ طابعَ المزامنة');
      expect(RegExp(r'function _tokenRolePayload\(').allMatches(idx).length, 1,
          reason: 'نسخةٌ ثانيةٌ من الحِمْلِ — وهي ما كان يَنحرِف');
      // ولا يُنشئُ رمزاً لمن لا رمزَ له — الرمزَ يَكتبُه الجهازُ وحدَه.
      expect(b, contains('if (!tokSnap.exists) return null;'));
    });

    test('(ه) المحرّرانِ كلاهما يُنادِيانِ النداءَ ولا يَحذفانِ مباشرةً', () {
      final fl = _code(_read('lib/screens/admin/admin_managers_screen.dart'));
      expect(fl, contains("httpsCallable('deleteStaffAccount')"));
      expect(fl.contains("collection('admins').doc(widget.docId).delete()"), isFalse);
      expect(fl.contains("collection('users').doc(widget.docId).delete()"), isFalse);
      final pn = _code(_read('admin_panel/src/pages/Admins.tsx'));
      expect(pn, contains("httpsCallable(functions, 'deleteStaffAccount')"));
      expect(pn.contains('deleteDoc('), isFalse,
          reason: 'حذفٌ مباشرٌ من اللوحةِ يُعيدُ الثغرةَ كاملةً');
      // وفشلُ الحذفِ يُقال — كان `try/finally` بلا `catch` إطلاقاً.
      expect(pn, contains('toast.error('));
    });

    test('(و) القاعدةُ ما زالت مُنفَّذةً في مسارِ السائق — المرجعُ لا يُنقَض', () {
      final b = _code(_export(idx, 'deleteDriverAccount'));
      for (final col in ['fcm_tokens', 'fcm_token']) {
        expect(b, contains('collection("$col").doc(driverId)'), reason: col);
      }
      expect(b, contains('getAuth().deleteUser(driverId)'));
    });

    test('(ز) نسخةُ الدورِ على الرمزِ هي فعلاً ما يُوجَّهُ عليه البثّ', () {
      // لو تغيّرَ مصدرُ التوجيهِ فالإصلاحُ كلُّه يُراجَعُ لا يُسكَت.
      expect(code, contains('tokQuery.where("role", "==", "client")'));
      expect(code, contains('where("staff_role", "in", targetRoles)'));
    });

    test('(ح) تنظيفُ الرموزِ الميتةِ صارَ بالمعرّفِ لا باستعلامٍ ميّت', () {
      // كان `where("token","==",bad)` والعميلُ يَكتبُ `fcmToken` وحدَه، ولا
      // شيءَ في المستودعِ يَكتبُ `token` — فالاستعلامُ لا يُطابقُ مستنداً
      // أبداً، والسطرُ يَطبعُ `cleaned=N` لِـN لم يُحذَف منها شيء.
      expect(code.contains('where("token", "==", bad)'), isFalse);
      expect(code, contains('refByToken'));
      expect(code, contains('cleaned=\${cleaned}'));
      // والعميلُ ما زال يَكتبُ `fcmToken` — وهو ما جعلَ الاستعلامَ ميّتاً.
      final svc = _read('lib/services/notification_service.dart');
      expect(svc, contains("'fcmToken': token"));
      // مقابلةُ الخامّ: الشرحُ ما زال يَذكرُ الاستعلامَ المُزال.
      expect(idx.contains('where("token","==",bad)') ||
          idx.contains('where("token", "==", bad)'), isTrue,
          reason: 'الحجبُ أفرغَ الفحصَ — الشرحُ يَذكرُ الاستعلامَ المُزال');
    });
  });
}
