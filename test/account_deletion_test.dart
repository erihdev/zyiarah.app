import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **حذفُ الحساب: مالٌ يُحجَز إلى الأبد، ونصٌّ يَعِدُ بما لا يحدث.**
///
/// ═══ ١. الرصيدُ المحجوز ═══
///
/// `processAccountDeletion` يَحذفُ حسابَ المصادقةِ ووثيقةَ `users/{uid}`
/// ورموزَ الإشعارات — ولا شيءَ فيه كان يَنظرُ إلى `wallets/{uid}`. فتُحذف
/// هويّةُ المصادقةِ ويبقى الرصيدُ في وثيقةٍ مفتاحُها معرّفٌ **لا يستطيع أحدٌ
/// تسجيلَ الدخولِ به بعد اليوم**: مالُ العميلةِ محجوزٌ إلى الأبد، بلا إشعارٍ
/// ولا سجلِّ دَينٍ في أيِّ مكان. وشاشةُ الملفِّ — وهي تَعرفُ الرصيدَ
/// (`_walletBalance` مُحمَّلٌ فيها) — لم تكن تَذكرُه في حوارِ التأكيد.
///
/// ولا نُصفّرُ المحفظة: التصفيرُ يُتلف الدليلَ على الدَّين. نُسجّلُ الرصيدَ
/// على `account_deletions/{uid}`، ونَسِمُ المحفظةَ `owner_deleted`، ونُنبّه
/// `super_admin`/`accountant_admin` لتُسوّى يدويّاً. والحذفُ **يَمضي**:
/// حقُّ الحذفِ متطلّبٌ من Apple ولا يُحجَب بدَينٍ على المنشأة.
///
/// ═══ ٢. نصُّ الحوار ═══
///
/// كان يَقول «سيتم مسح كافة بياناتك، **فواتيرك**، وخدماتك السابقة نهائياً»
/// و«حق النسيان: سيتم حذف **كافة سجلات التتبع** الخاصة بك». والاثنان غيرُ
/// صحيحَين: الفاتورةُ الضريبيّةُ والطلبُ يُحفظان بحكمِ نظامِ ضريبةِ القيمةِ
/// المضافة، و`processAccountDeletion` لا يَمسُّ `orders` إطلاقاً — تَبقى
/// حاملةً `client_name`/`client_phone`/`client_email` كما سُجّلت.
///
/// وأوّلُ صياغةٍ لهذا الإصلاحِ استبدلت الكذبةَ بأخرى («يُجهَّل ما تبقّى») —
/// ولا شيءَ في المستودعِ يُجهّل طلباً. فالنصُّ الآن يَصفُ ما يحدثُ حرفيّاً،
/// وهذا الملفُّ يَحرسُ أنّه كذلك.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();

  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  group('الخادم: الرصيدُ المحجوز', () {
    late String body;

    setUpAll(() {
      final idx = read('functions/index.js');
      final i = idx.indexOf('async function processAccountDeletion(uid)');
      expect(i, greaterThan(0), reason: 'الدالّةُ غائبة');
      final j = idx.indexOf('\n// 8a.', i);
      expect(j, greaterThan(i));
      body = stripLineComments(idx.substring(i, j));
    });

    test('يَقرأُ المحفظةَ **قبل** حذفِ حسابِ المصادقة', () {
      final wallet = body.indexOf('collection("wallets")');
      final auth = body.indexOf('getAuth().deleteUser(');
      expect(wallet, greaterThan(0), reason: 'لا يَنظرُ إلى المحفظةِ أصلاً');
      expect(auth, greaterThan(0));
      expect(wallet, lessThan(auth),
          reason: 'قراءةٌ بعد حذفِ المصادقةِ لا تَمنعُ الحجز — الترتيبُ هو الفحص');
    });

    test('يُسجّلُ الرصيدَ على طلبِ الحذفِ ويَسِمُ المحفظة', () {
      expect(body, contains('wallet_balance_at_deletion'),
          reason: 'الدَّينُ غيرُ مكتوبٍ في مكانٍ يَقرؤه البشر');
      expect(body, contains('owner_deleted'));
      expect(body, contains('owner_deleted_at'));
    });

    test('يُنبّهُ المحاسبةَ عند رصيدٍ موجبٍ فقط', () {
      expect(body, contains('admin_wallet_stranded'));
      expect(body, contains('"super_admin", "accountant_admin"'));
      expect(body, contains('if (strandedBalance > 0)'),
          reason: 'تنبيهٌ بلا شرطٍ = تنبيهٌ لكلِّ حذفٍ فيُهمَل');
    });

    test('ولا يُصفّرُ المحفظةَ — التصفيرُ يُتلف الدليلَ على الدَّين', () {
      expect(body.contains('balance: 0'), isFalse);
      expect(RegExp(r'balance:\s*FieldValue').hasMatch(body), isFalse);
    });

    test('ولا يَحجبُ الحذفَ بدَينٍ على المنشأة (متطلّبُ Apple)', () {
      // قراءةُ المحفظةِ في `try` خاصٍّ بها، وفشلُها لا يَرمي.
      final wallet = body.indexOf('collection("wallets")');
      final deleteUsers =
          body.indexOf('collection("users").doc(uid).delete()');
      expect(deleteUsers, greaterThan(wallet),
          reason: 'الحذفُ ما زال يَمضي بعد قراءةِ المحفظة');
      expect(body, contains('[deletion] wallet read failed'),
          reason: 'فشلُ قراءةِ المحفظةِ يجب أن يُسجَّل ولا يَرمي');
    });
  });

  group('الواجهة: الحوارُ يَقولُ ما يحدث', () {
    final profile = read('lib/screens/profile_screen.dart');

    test('يُحذَّر بالرصيدِ **قبل** التأكيد', () {
      final i = profile.indexOf('void _showDeleteConfirmation');
      expect(i, greaterThan(0));
      final j = profile.indexOf('Widget _buildDangerCard', i);
      final dialog = profile.substring(i, j > i ? j : profile.length);
      expect(dialog, contains('_walletBalance > 0'),
          reason: 'الرصيدُ مُحمَّلٌ في الشاشةِ ولا يُذكَر في الحوار');
      expect(dialog, contains('!_walletError'),
          reason: 'رصيدٌ لم يُجلَب ليس رصيداً صفرياً — لا نُحذّر بقيمةٍ وهميّة');
      // النصُّ مقطوعٌ بين حرفيَّتَين في المصدر (`... ر.س في '` ثمّ
      // `'محفظتك. ...`) فلا يُطابَق كسلسلةٍ واحدة — نَفحصُ الشقَّين.
      expect(dialog, contains('ر.س في '));
      expect(dialog, contains('محفظتك. استخدميها'));
      // والتحذيرُ يَذكرُ المبلغَ لا عبارةً مجرّدة.
      expect(dialog, contains('_walletBalance.toStringAsFixed(2)'));
    });

    test('لا يَزعُمُ حذفَ الفواتيرِ ولا سجلّاتِ التتبّعِ كلِّها', () {
      for (final lie in [
        'سيتم مسح كافة بياناتك، فواتيرك، وخدماتك السابقة نهائياً',
        'سيتم حذف كافة سجلات التتبع الخاصة بك',
      ]) {
        expect(profile.contains(lie), isFalse, reason: 'عادت الكذبة: $lie');
      }
      // وما يُقال الآن يُسمّي الاحتفاظَ وسببَه.
      expect(profile, contains('ضريبة القيمة المضافة'));
      expect(profile, contains('الاسم والجوّال'));
    });

    test('ولا يَزعُمُ تجهيلاً لا يَفعلُه أحد', () {
      // أوّلُ صياغةٍ لهذا الإصلاحِ استبدلت كذبةً بأخرى. لا شيءَ في المستودعِ
      // يُجهّل طلباً، فالكلمةُ ممنوعةٌ في نصٍّ معروضٍ حتى يُكتَبَ ما يُبرّرها.
      //
      // والتعليقُ في الشاشةِ يَذكرُ الكلمةَ ليَشرحَ القاعدة — فالفحصُ على
      // المصدرِ بعد تجريدِ التعليقات، ثمّ نؤكّد أنّها في الخامِّ كي لا يُفرِغَ
      // التجريدُ الفحصَ من موضوعه (هذا الحارسُ سقطَ على توثيقِه أوّلَ مرّة).
      final anonymises = read('functions/index.js').contains('anonymiz') ||
          read('functions/index.js').contains('anonymis');
      if (!anonymises) {
        expect(stripLineComments(profile).contains('يُجهَّل'), isFalse,
            reason: 'نصٌّ معروضٌ يَعِدُ بتجهيلٍ لا يَفعلُه أحد');
      }
      expect(profile.contains('يُجهَّل'), isTrue,
          reason: 'الكلمةُ اختفت من الملفِّ كلِّه — التعليقُ الذي يَحملُ '
              'القرارَ حُذف، فالفحصُ بلا موضوع');
    });
  });
}
