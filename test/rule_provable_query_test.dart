import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/strip_comments.dart';

/// **استعلامُ قائمةٍ لا يُثبِتُ قاعدتَه يُرفَضُ في وجهِ العميلةِ وحدَها.**
///
/// قواعدُ Firestore ليست مُرشِّحات: استعلامُ **قائمةٍ** يُرفَضُ كلُّه ما لم
/// تَضمَنْ قيودُه أنّ كلَّ مستندٍ يُعيدُه يُحقّقُ الشرط. فمجموعةٌ شرطُها
/// `resource.data.X == uid` لا تُستعلَمُ إلّا بمُرشِّحٍ على `X`.
///
/// ولا شيءَ يَكشفُ ذلك قبلَ التشغيل: الشفرةُ تُترجَمُ، و`analyze` نظيفٌ، وكلُّ
/// الفحوصِ تَمرُّ — والفشلُ `permission-denied` عند التنفيذِ، وغالباً داخلَ
/// `try` يَسقطُ على حالةٍ تَبدو مشروعة. وُجد هذا الصنفُ مرّةً في `promo_codes`
/// وأُصلح هناك وحدَه؛ **والقاعدةُ عامّةٌ**، فهذا قارئُها.
///
/// وثلاثةٌ وُجدت بمسحٍ عامٍّ ثمّ **أُثبِتت على مُحاكي القواعد** لا استنتاجاً:
///   • `users` بـ`referral_code` — فحصُ تصادمِ كودِ الإحالةِ في العميل: كان
///     يَرمي، فلا عميلةَ تَحصلُ على كودٍ أبداً. انتقلَ إلى
///     `exports.ensureReferralCode`.
///   • `orders` بـ`contract_id` وحدَه — جدولُ زياراتِ عقدٍ في الـPDF: يَسقطُ
///     على `catch` فيُطبَعُ العقدُ بلا مواعيد، **للأدمنِ يَعملُ ولها لا**.
///     أُضيفَ مُرشِّحُ مالكِ العقد.
///   • `drivers` بـ`phone` — احتياطُ تحديدِ الدور: يَفشلُ مُغلَقاً (شاشةُ
///     «الدورُ غيرُ متاح») وبقي موثَّقاً أنّه غيرُ قابلٍ للنجاح.
String _code(String path) => stripComments(File(path).readAsStringSync());

/// المجموعاتُ التي شرطُ قراءتِها يُفحَصُ على **حقلٍ في المستند**، ومعها
/// الحقولُ التي يُثبِتُ أحدُها الشرط. (المجموعاتُ المُفتاحةُ بمعرّفِ المستندِ —
/// `wallets`, `drivers`, `users`, `admins`, `fcm_tokens` — لا تُستعلَمُ قائمةً
/// من عميلٍ بحال، فأيُّ استعلامٍ عليها مخالفةٌ بذاتِه.)
const Map<String, List<String>> kProvingFilters = {
  'orders': ['client_id', 'driver_id'],
  'store_orders': ['client_id'],
  'contracts': ['userId'],
  'notifications': ['userId'],
  'support_tickets': ['userId'],
  'tickets': ['userId'],
  'notifications_log': ['type'],
  'promo_codes': ['show_in_offers', 'target_user_id'],
  'referrals': ['referee_id', 'referrer_id'],
};

/// المجموعاتُ المُفتاحةُ بمعرّفِ المستندِ: لا مُرشِّحَ يُثبِتُ شرطَها.
const Set<String> kDocIdOnly = {
  'users',
  'drivers',
  'wallets',
  'admins',
  'fcm_tokens',
  'fcm_token',
  'accountants',
};

/// استعلاماتٌ باقيةٌ لا تُثبِتُ شرطَها، ولكلٍّ سببُه. المفتاحُ `<ملف>#<ترتيب>`
/// لا رقمُ سطرٍ، فتعديلٌ أعلى الملفِّ لا يُسقطُ الحارسَ زوراً.
const Map<String, String> kAllowedUnprovable = {
  // احتياطُ تحديدِ الدورِ: يَفشلُ مُغلَقاً إلى شاشةِ «الدورُ غيرُ متاح»، ولا
  // يُغيّرُ إسقاطُه سلوكاً — موثَّقٌ في موضعِه بأنّه غيرُ قابلٍ للنجاح.
  'lib/services/firebase_service.dart#0':
      'احتياطُ الدورِ بـphone — يَفشلُ مُغلَقاً وموثَّقٌ',
};

/// جسمُ نداءٍ من ترويسةٍ مُسمّاةٍ **بموازنةِ أقواسِ النداءِ** لا المعقوفة.
///
/// فخّانِ وقعا هنا، كلاهما مسجَّلٌ في هذا المستودع: (١) `contains` على الملفِّ
/// كلِّه يُجوِّفُ الفحصَ متى شارَكَ النصُّ دالّةً أخرى — و`applyReferralCode`
/// يَحملُ استعلامَ `referral_code` نفسَه، فمرَّت قضمةٌ حذفت فحصَ التصادمِ
/// **أخضرَ**؛ و(٢) موازنةُ **المعقوفةِ** من الترويسةِ تَتوقّفُ عند كائنِ
/// الخياراتِ `{cpu: …}` لا عند جسمِ الدالّة. فالموازنةُ على `(` النداء.
String _callBody(String code, String header) {
  final i = code.indexOf(header);
  if (i < 0) throw StateError('ترويسةٌ مفقودة: $header');
  final open = code.indexOf('(', i);
  if (open < 0) throw StateError('لا قوسَ نداءٍ بعد: $header');
  var depth = 0;
  for (var j = open; j < code.length; j++) {
    if (code[j] == '(') depth++;
    if (code[j] == ')') {
      depth--;
      if (depth == 0) return code.substring(i, j + 1);
    }
  }
  throw StateError('تعذّرَ موازنةُ: $header');
}
void main() {
  group('كلُّ استعلامِ قائمةٍ عميليٍّ يُثبِتُ قاعدتَه', () {
    test('(أ) مسحٌ مُشتَقٌّ على كلِّ شفرةِ العميلِ والسائق', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('/admin/'))
          .where((f) => !f.path.split('/').last.startsWith('admin_'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, greaterThanOrEqualTo(80),
          reason: 'المسحُ لم يَقرأ شفرةَ العميل — نطاقٌ منهار');

      final offenders = <String, String>{};
      var scanned = 0;
      for (final f in files) {
        final code = _code(f.path);
        var ord = 0;
        for (final m
            in RegExp(r"\.collection\(\s*'([a-z_]+)'\s*\)").allMatches(code)) {
          final col = m.group(1)!;
          if (!kProvingFilters.containsKey(col) && !kDocIdOnly.contains(col)) {
            continue;
          }
          final tail = code.substring(
              m.end, (m.end + 900).clamp(0, code.length));
          // قراءةُ مستندٍ بمعرّفِه ليست استعلامَ قائمة
          if (RegExp(r'^\s*\.doc\(').hasMatch(tail)) continue;
          final term = RegExp(r'\.(get|snapshots|count)\s*\(').firstMatch(tail);
          if (term == null) continue; // ليست قراءةً (إضافةٌ مثلاً)
          final chain = tail.substring(0, term.end);
          if (!chain.contains('.where(')) continue; // بلا مُرشِّحٍ: ليست هذه الحالة
          scanned++;
          final proven = kDocIdOnly.contains(col)
              ? false
              : kProvingFilters[col]!
                  .any((fld) => chain.contains("'$fld'"));
          if (!proven) {
            offenders['${f.path}#$ord'] = col;
            ord++;
          }
        }
      }
      expect(scanned, greaterThanOrEqualTo(15),
          reason: 'عددُ الاستعلاماتِ المفحوصةِ انهارَ — كاشفٌ أجوف');
      expect(offenders.keys.toSet(), kAllowedUnprovable.keys.toSet(),
          reason: 'استعلامُ قائمةٍ لا يُثبِتُ قاعدتَه: يُرفَضُ عند العميلةِ '
              'دائماً ولا يَكشفُه فحصٌ قبلَ التشغيل. offenders=$offenders');
    });

    test('(ب) كودُ الإحالةِ يُولَّدُ خادميّاً ولا نسخةَ عميليّة', () {
      final svc = _code('lib/services/zyiarah_referral_service.dart');
      expect(RegExp(r"httpsCallable\(\s*'ensureReferralCode'\s*\)")
          .hasMatch(svc), isTrue,
          reason: 'العميلُ لا يُنادي التوليدَ الخادميّ');
      expect(svc.contains("where('referral_code'"), isFalse,
          reason: 'فحصُ التصادمِ العميليُّ عادَ — وهو مرفوضٌ بالقواعدِ دائماً');
      expect(svc.contains('_generateCode'), isFalse,
          reason: 'مُولِّدُ الكودِ العميليُّ عادَ');
      final idx = _code('functions/index.js');
      expect(idx, contains('exports.ensureReferralCode = onCall('));
      // **جسمُ الدالّةِ وحدَه**: `applyReferralCode` يَحملُ استعلامَ
      // `referral_code` نفسَه، فـ`contains` على الملفِّ كلِّه مرَّ **أخضرَ**
      // على قضمةٍ حذفت فحصَ التصادم — أُثبِتَ بالقضم.
      final body = _callBody(idx, 'exports.ensureReferralCode = onCall');
      expect(body, contains('.where("referral_code", "==", code).limit(1)'),
          reason: 'فحصُ التصادمِ الخادميُّ زالَ — فالكودُ قد يَتكرّرُ وإسنادُ '
              'مكافأةِ الإحالةِ يَخطئ');
      // **القدرةُ لا الاسم**: `contains('db.runTransaction')` يُرضيه سطرٌ
      // مُعطَّلٌ بجوارِ كتابةٍ مباشرة — أُثبِتَ بقضمةٍ مرَّت أخضرَ. فالمشدودُ
      // أن تَكونَ الكتابةُ **داخلَ** المعامَلةِ وأن لا كتابةَ مباشرةً معها.
      expect(RegExp(r't\.update\(\s*userRef').hasMatch(body), isTrue,
          reason: 'الكتابةُ ليست داخلَ المعامَلةِ — نداءانِ متزامنانِ '
              'يُنتجانِ كودَين لعميلةٍ واحدة');
      expect(RegExp(r'await\s+userRef\.update\(').hasMatch(body), isFalse,
          reason: 'كتابةٌ مباشرةٌ خارجَ المعامَلةِ تَنقضُ الذرّيّة');
      expect(body, contains('throw new HttpsError("unauthenticated"'),
          reason: 'النداءُ بلا مصادقة');
    });

    test('(ج) جدولُ زياراتِ العقدِ يُرشَّحُ بمالكِه في المُنادِيَين', () {
      final pdf = _code('lib/services/zyiarah_pdf_service.dart');
      expect(pdf, contains("where('client_id', isEqualTo: ownerUid)"),
          reason: 'مُرشِّحُ المالكِ زالَ — فالجدولُ لا يُطبَعُ للعميلةِ أبداً');
      for (final caller in [
        'lib/screens/contracts_list_screen.dart',
        'lib/screens/admin/admin_contracts_screen.dart',
      ]) {
        expect(RegExp(r"ownerUid:\s*data\['userId'\]").hasMatch(_code(caller)),
            isTrue,
            reason: '$caller لا يُمرّرُ مالكَ العقد');
      }
    });

    test('(د) شاهدا التعليل: القاعدتانِ ما زالتا مشروطتَين', () {
      final rules = _code('firestore.rules');
      expect(rules, contains('isOwner(userId) || isAdmin()'),
          reason: 'قاعدةُ `users` لم تَعُد مشروطةً — فتعليلُ النقلِ الخادميِّ '
              'يُراجَعُ لا يُفترَض');
      expect(rules, contains("request.auth.uid == resource.data.client_id"),
          reason: 'قاعدةُ `orders` لم تَعُد تَفحصُ `client_id`');
      expect(rules, contains('request.auth.uid == driverId || isAdmin()'),
          reason: 'قاعدةُ `drivers` لم تَعُد مُفتاحةً بالمعرّف — فاحتياطُ '
              'الدورِ قد يَصيرُ قابلَ النجاحِ ويُراجَعُ توثيقُه');
    });
  });
}
