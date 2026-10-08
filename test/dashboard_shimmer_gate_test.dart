// **شِمِرُّ الرئيسيّةِ كان يَنتظرُ استعلاماً لا يُرسَمُ ناتجُه في أيِّ موضع.**
//
// `ZyiarahOrderProvider` كان يُسجَّلُ في `main.dart` لـ**كلِّ** جلسة، فيَفتحُ
// مستمعاً على `orders` لكلِّ عميلةٍ عند أوّلِ إقلاعٍ ويُرتّبُ عشرينَ مستنداً
// محلّيّاً — **ولا قارئَ لشيءٍ من ذلك**: `recentOrders` لا يَقرؤها إلّا
// `activeOrders`، و`activeOrders` بلا قارئٍ في المستودعِ كلِّه. فالعضوُ الحيُّ
// الوحيدُ كان `isLoading`، ووحيدُ قارئِه سطرٌ في `client_dashboard`:
//
//     final isLoading = userProvider.isLoading || orderProvider.isLoading;
//     body: isLoading ? _buildShimmerLoading() : …
//
// أي أنّ **الصفحةَ الرئيسيّةَ كلَّها** تَبقى شِمِرّاً حتى يَرجعَ ذلك الاستعلامُ
// — إلى `kNetCallTimeout` (٢٠ث) على ذاكرةٍ باردةٍ وخادمٍ غيرِ قابلِ الوصول،
// **بعدَ** أن يَكونَ الملفُّ الشخصيُّ قد وصلَ وصارت الشاشةُ قابلةً للرسم. ولا
// شيءَ أسفلَ الشِمِرِّ يَقرأُ حرفاً مِمّا حُمِّل: بطاقةُ التتبّعِ وبطاقاتُ
// الباقاتِ وشريطُ العروضِ كلٌّ له `StreamBuilder` بحالاتِه الخاصّة.
//
// وهو شكلُ `GeofenceService.supportedZones` المسجَّلُ في `CLAUDE.md`
// («استعلامٌ في كلِّ إقلاعٍ لمخزَنٍ قارئُه الوحيدُ بلا قارئ») — إلّا أنّ هذا
// كان يُبطِئُ الشاشةَ الأولى، وذاك كان يُهدِرُ قراءةً بصمت.
//
// فحُذِفَ المُزوِّدُ، وصارَ الشِمِرُّ على `userProvider.isLoading` وحدَه — وهو
// بعينِه ما تَرسُمُه الشاشةُ (`user?.uid` وبانرُ خطأِ الملفِّ الشخصيّ).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

void main() {
  final dashRaw = File('lib/screens/client_dashboard.dart').readAsStringSync();
  final dash = stripComments(dashRaw);
  final mainCode = stripComments(File('lib/main.dart').readAsStringSync());

  /// جسمُ دالّةٍ بموازنةِ المعقوفةِ **بعدَ** قائمةِ المعامَلات — `indexOf('{')`
  /// يَلتقطُ قوسَ المعامَلاتِ المُسمّاةِ، وهو فخٌّ مسجَّلٌ هنا سبعَ مرّات.
  String body(String src, String sig) {
    final i = src.indexOf(sig);
    expect(i, greaterThan(-1), reason: 'لم تُوجَد $sig');
    var j = src.indexOf('(', i);
    var d = 0;
    for (; j < src.length; j++) {
      if (src[j] == '(') d++;
      if (src[j] == ')') {
        d--;
        if (d == 0) break;
      }
    }
    final open = src.indexOf('{', j);
    expect(open, greaterThan(j));
    d = 0;
    for (var k = open; k < src.length; k++) {
      if (src[k] == '{') d++;
      if (src[k] == '}') {
        d--;
        if (d == 0) return src.substring(open, k + 1);
      }
    }
    throw StateError('جسمٌ غيرُ مُوازَنٍ: $sig');
  }

  test('(١) بوّابةُ الشِمِرِّ تَقرأُ المُزوِّدَ الذي تَرسُمُه وحدَه', () {
    final m = RegExp(r'final isLoading = ([^;]*);').firstMatch(dash);
    expect(m, isNotNull, reason: 'سطرُ بوّابةِ الشِمِرِّ لم يُوجَد');
    final expr = m!.group(1)!;
    expect(expr, contains('userProvider.isLoading'));
    // **ولا مُزوِّدٌ ثانٍ في التعبير**: إضافةُ `|| xProvider.isLoading` تَعني
    // أنّ الشاشةَ تَنتظرُ حملاً آخرَ — فيَلزمُ أن تَرسُمَ منه شيئاً.
    expect(RegExp(r'\w+Provider\.isLoading').allMatches(expr).length, 1,
        reason: 'الشِمِرُّ يَنتظرُ أكثرَ من حملٍ واحد: $expr');
  });

  test('(٢) المُزوِّدُ لم يَعُدْ يُسجَّلُ ولا ملفُّه قائم', () {
    expect(mainCode, isNot(contains('ZyiarahOrderProvider')),
        reason: 'عادَ تسجيلُ مُزوِّدٍ يَستعلمُ `orders` لكلِّ عميلةٍ عند '
            'الإقلاعِ بلا قارئٍ لناتجِه');
    expect(dash, isNot(contains('ZyiarahOrderProvider')));
    expect(File('lib/providers/order_provider.dart').existsSync(), isFalse);
  });

  test('(٣) ولا قارئَ للمخزَنِ المحذوفِ في المستودعِ — فرضيّةُ الحذف', () {
    // الحذفُ قامَ على أنّ `recentOrders`/`activeOrders` بلا قارئ. فلو ظهرَ
    // قارئٌ غداً فالقرارُ يُراجَعُ لا يُسكَت — ومعه يُراجَعُ ما إذا كان
    // المُزوِّدُ لازماً حقّاً.
    final offenders = <String>[];
    final files = sourcesIn('lib', atLeast: 150);
    for (final f in files) {
      final code = stripComments(f.readAsStringSync());
      for (final n in const ['recentOrders', 'activeOrders']) {
        if (RegExp('${r'\.\s*'}$n${r'\b'}').hasMatch(code)) {
          offenders.add('${f.uri.pathSegments.last} ← $n');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'قارئٌ لمخزَنٍ محذوف: $offenders');
  });

  test('(٤) وكلُّ بطاقةٍ أسفلَ الشِمِرِّ لها بثُّها — فلا شيءَ فُقِد', () {
    // لو كانت إحداها تَقرأُ من المُزوِّدِ لكانَ الحذفُ إسقاطَ محتوى. الثلاثُ
    // تَبني من `StreamBuilder` بحالاتِها (ومنها فرعُ الخطأ، بقرارِ
    // `stream_error_branch_test`).
    for (final sig in const [
      'Widget _buildActiveTrackingCard(String? uid)',
      'Widget _buildSubscriptionCards(String? uid)',
      'Widget _buildPromoBanners()',
    ]) {
      expect(body(dash, sig), contains('StreamBuilder'),
          reason: '$sig لا تَبني من بثٍّ — فبوّابةُ الشِمِرِّ قد تَكونُ '
              'حاملةً لها');
    }
  });

  test('(٥) وجالبُ «حالة الطلب» المحذوفُ لا يَعود', () {
    // `ZyiarahStrings.orderStatus` كان بلا قارئ، و**الذي أحياهُ في الفحصِ
    // العامِّ متغيّرٌ محلّيٌّ بالاسمِ نفسِه** في `admin_order_details_screen`
    // — وهو ما شدَّدَ `no_dead_code_test` في هذه الدفعة.
    final strings =
        stripComments(File('lib/utils/zyiarah_strings.dart').readAsStringSync());
    expect(strings, isNot(contains('get orderStatus')),
        reason: 'عادَ جالبٌ بلا قارئٍ يُحييه تَصادُفُ اسم');
    // **وشاهدُ التعليلِ لا مضادّةٌ دائريّة**: أوّلُ صياغةٍ شدَّت الاسمَ في
    // نصِّ هذا الملفِّ نفسِه — وهو يَحويه في سطرِ التأكيدِ أعلاه، فالمضادّةُ
    // لا تَسقطُ أبداً (قضمةٌ أثبتَت ذلك). فالمشدودُ هو **الحالةُ التي
    // أوجبَت التشديد**: متغيّرٌ محلّيٌّ بالاسمِ نفسِه في شاشةِ تفاصيلِ
    // الطلبِ — فلو زالَ لَزِمَ مراجعةُ تعليلِ `no_dead_code_test` لا إسكاتُه.
    final det = stripComments(
        File('lib/screens/admin/admin_order_details_screen.dart')
            .readAsStringSync());
    expect(det, matches(RegExp(r'\b(?:final|var)\s+orderStatus\s*=')),
        reason: 'زالَ المتغيّرُ المحلّيُّ الذي كان يُحيي الجالب — فتعليلُ '
            'تشديدِ `no_dead_code_test` يُراجَع');
  });

  test('(٦) وتعليقُ خدمةِ المصادقةِ لا يُسمّي صنفاً زال', () {
    // ادّعاءٌ عن صنفٍ لا وجودَ له يُضلِّلُ قارئَه — عائلةُ «ادّعاءٌ بلا قارئ».
    final svc = File('lib/services/firebase_service.dart').readAsStringSync();
    expect(svc, isNot(contains('ZyiarahOrderProvider')));
    expect(svc, contains('ZyiarahUserProvider'),
        reason: 'المُزوِّدُ الباقي يَجبُ أن يَبقى مذكوراً — وإلّا فالتعليقُ '
            'لم يُصحَّحْ بل أُفرِغ');
  });
}
