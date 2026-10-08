import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyasar/moyasar.dart';
import 'package:zyiarah/utils/moyasar_error_text.dart';
import 'helpers/strip_comments.dart';

/// **ثلاثةُ مساراتِ دفعٍ أصليٍّ، وقرارٌ واحدٌ مكتوبٌ ثلاثَ مرّاتٍ فسقطت منه
/// حالاتٌ في كلِّ نسخة.**
///
/// Apple Pay و Samsung Pay يَمُرّانِ بحزمةِ ميسر فيَصِلُهما
/// `PaymentResponse`/`ApiError`/`ValidationError`/`NetworkError`؛ وGoogle Pay
/// يَمُرُّ بـ`http.post` مباشرةً. والقرارُ الذي يَشتركونَ فيه قرارانِ:
///
/// **١. «لا نعرف» ليست «فشل».** انقطاعُ شبكةٍ أو مهلةٌ تَترُكُ النتيجةَ
/// مجهولةً — وقد يكون المبلغُ خُصم — فالرسالةُ تَقولُ ذلك ولا تَدّعي الفشل.
/// كان الفرعُ موجوداً في Samsung Pay وحدَه: Apple Pay (مسارُ الدفعِ الأصليِّ
/// على iOS) تَقولُ «فشل الدفع عبر Apple Pay» لانقطاعِ شبكةٍ، وGoogle Pay
/// تَطبعُ `e.toString()` خامّاً فتُقرأُ «TimeoutException after
/// 0:00:30.000000: Future not completed» بحرفٍ لاتينيٍّ في شريطٍ عربيّ.
///
/// **٢. وتجديدُ `given_id` عند فشلٍ سجّلته ميسر وحدَه.** دفعةٌ سُجِّلت
/// تَستهلكُ المعرّفَ، فإعادةُ المحاولةِ به تُعيدُ الفشلَ نفسَه؛ وما لا
/// نَعرفُ نتيجتَه يُبقيه منعاً للشحنِ المزدوج. وهذا القرارُ **غابَ عن Google
/// Pay كلَّه**: كلُّ فشلٍ كان يُعيدُ المحاولةَ بالمعرّفِ المُستهلَك.
///
/// فالفرقُ بين المسارَين الأوّلَين حالةٌ ناقصةٌ، وفي الثالثِ قرارٌ كامل —
/// وكلُّه من «قاعدةٌ عامّةٌ مُنفَّذةٌ في سطحٍ واحد».
void main() {
  final screen = stripComments(
      File('lib/screens/payment_summary_screen.dart').readAsStringSync());
  final svc = stripComments(
      File('lib/services/moyasar_service.dart').readAsStringSync());

  /// كتلةٌ بموازنةِ الأقواسِ من موضعِ بدايةٍ — لا نافذةَ عدِّ أحرفٍ ولا
  /// `indexOf` لأوّلِ إغلاق (فخُّ الحدِّ، مسجَّلٌ في هذا المستودعِ سبعَ مرّات).
  String parenBlock(String src, int start) {
    final open = src.indexOf('(', start);
    var depth = 1;
    var i = open + 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') depth--;
      i++;
    }
    return src.substring(start, i);
  }

  /// جملةُ «النتيجةُ مجهولة» — تُشتَقُّ من المصدرِ ولا تُكتَبُ في الفحص، فلو
  /// صِيغت غداً بكلماتٍ أخرى بَقِيَ الفحصُ يُقارِنُ الثلاثةَ ببعضِها.
  const unknownMark = 'إن كان المبلغُ قد خُصم فلا تقلقي';

  /// جسمُ دالّةٍ من موضعِ إعلانِها — **بموازنةِ قائمةِ المعامَلاتِ أوّلاً**
  /// ثمّ المعقوفة. أخذُ أوّلِ `{` بعدَ الاسمِ يَلتقطُ قوسَ المعامَلاتِ
  /// المُسمّاة، وهو فخُّ الحدِّ المسجَّلُ في هذا المستودعِ عشرَ مرّات.
  String fnBody(String src, int declAt) {
    final open = src.indexOf('(', declAt);
    var depth = 1;
    var i = open + 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') depth--;
      i++;
    }
    final brace = src.indexOf('{', i);
    if (brace < 0) throw StateError('لم يُوجَد جسمُ الدالّةِ عند $declAt');
    depth = 1;
    var j = brace + 1;
    while (j < src.length && depth > 0) {
      if (src[j] == '{') depth++;
      if (src[j] == '}') depth--;
      j++;
    }
    final body = src.substring(brace, j);
    if (body.length < 40) throw StateError('اقتطاعُ الجسمِ انهارَ عند $declAt');
    return body;
  }

  /// كتلةٌ بموازنةِ المعقوفةِ من موضعِ `if (…) {` — لا `indexOf('}')`.
  String braceBody(String src, int at) {
    final brace = src.indexOf('{', at);
    if (brace < 0) throw StateError('لا كتلةَ عند \$at');
    var depth = 1;
    var i = brace + 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') depth--;
      i++;
    }
    final body = src.substring(brace, i);
    if (body.length < 30) throw StateError('اقتطاعُ الكتلةِ انهارَ عند \$at');
    return body;
  }

  /// نصُّ الوحدةِ — الجملةُ تَسكنُ هناك، فالفحصُ يَقرؤها من مصدرِها.
  final String rule = stripComments(
      File('lib/utils/moyasar_error_text.dart').readAsStringSync());


  test('(١) جملةُ النتيجةِ المجهولةِ تَسكنُ الوحدةَ — لا نسخةَ في الشاشة', () {
    // كانت مكتوبةً **ثلاثَ مرّاتٍ** في هذه الشاشةِ بصياغةٍ تُخالِفُ
    // `kMoyasarUnknownResult` في الشيءِ الوحيدِ الذي يُهمّ: «**وإلّا فأعيدي
    // المحاولة**» مقابلَ «لا تُعيدي الدفع». فالمجموعةُ كاملةً تُقابَلُ
    // باستثناءٍ واحدٍ مُعلَّلٍ — وهو حوارٌ آخرُ لسطحٍ آخر.
    expect(rule.contains(unknownMark), isTrue,
        reason: 'الجملةُ ليست في الوحدةِ — فلا مصدرَ لها');
    const walletDialogMark = 'لن يُخصم منك مرتين';
    final hits = unknownMark.allMatches(screen).toList();
    expect(hits.length, 1,
        reason: 'الجملةُ في ${hits.length} موضعٍ من الشاشة — نسخةٌ محلّيّةٌ '
            'تَنحرِفُ عن الوحدةِ كما انحرفت الثلاثُ السابقة');
    final h = hits.single;
    final near = screen.substring((h.start - 500).clamp(0, screen.length),
        (h.end + 500).clamp(0, screen.length));
    expect(near.contains(walletDialogMark), isTrue,
        reason: 'الموضعُ الباقي ليس حوارَ المحفظةِ المُستثنى — وهو سطحٌ آخر '
            '(بلا معرّفِ دفعةٍ، ومعه رقمٌ مرجعيٌّ) فلا يُفوَّضُ إلى قاعدةِ '
            'أخطاءِ البوّابة');
  });

  test('(٢) ولكلِّ مسارٍ طريقُه إلى الوحدة — لا مُبدِّلٌ محلّيّ', () {
    // Apple/Samsung: الفرعُ كلُّه مُفوَّضٌ إلى دالّةٍ واحدةٍ تُنادي القاعدة.
    for (final fn in ['_onApplePayResult', '_onSamsungPayResult']) {
      final i = screen.indexOf('$fn(dynamic result)');
      expect(i, greaterThan(-1), reason: 'لم يُوجَد $fn');
      final body = fnBody(screen, i);
      expect(body.contains('_handleNativePayFailure('), isTrue,
          reason: '$fn لا يُفوّضُ القرارَ — فعادت النسخةُ المحلّيّة');
      // ولا قراءةَ لرسالةِ البوّابةِ في الفرع.
      expect(RegExp(r'result\.message').hasMatch(body), isFalse,
          reason: '$fn يَقرأُ `result.message` — وهو `jsonBody[\'message\']` '
              'من ميسر أي إنجليزيٌّ في شريطٍ عربيّ');
    }
    // والمُفوَّضُ إليه يُنادي القاعدةَ ويَعرضُ ناتجَها.
    final hi = screen.indexOf('_handleNativePayFailure(dynamic result');
    expect(hi, greaterThan(-1), reason: 'لم تُوجَد الدالّةُ المشترَكة');
    final shared = fnBody(screen, hi);
    expect(shared.contains('moyasarErrorText('), isTrue,
        reason: 'الدالّةُ المشترَكةُ لا تُنادي القاعدة');
    expect(RegExp(r'Text\(\s*e\.message').hasMatch(shared), isTrue,
        reason: 'ناتجُ القاعدةِ لا يُعرَض — فالنداءُ زينة');
    expect(RegExp(r'Text\(\s*e\.detail').hasMatch(shared), isFalse,
        reason: 'التشخيصُ يُعرَضُ للعميلة');
    // ولا نسخةَ من المُبدِّلِ باقيةٌ في الشاشةِ كلِّها.
    for (final t in const [
      'result is ApiError',
      'result is ValidationError',
      'result is NetworkError',
    ]) {
      expect(screen.contains(t), isFalse,
          reason: 'عادَ مُبدِّلٌ محلّيٌّ لأنواعِ أخطاءِ الحزمة: $t');
    }
    // Google Pay: فرعُه المفهومُ من الخدمة، والمجهولُ من الوحدة.
    final g = screen.indexOf('onPaymentResult: (result) async {');
    expect(g, greaterThan(-1), reason: 'لم يُوجَد مُعالِجُ Google Pay');
    final gpay = screen.substring(g, g + 2900);
    expect(gpay.contains('on MoyasarPayFailure catch'), isTrue,
        reason: 'Google Pay لا يُميّزُ الفشلَ المفهومَ من المجهول');
    expect(gpay.contains('kMoyasarUnknownResult'), isTrue,
        reason: 'المسارُ المجهولُ في Google Pay يَكتبُ صياغتَه — وكانت '
            'تَدعو إلى الإعادة');
  });

  test('(٣) تجديدُ المعرّفِ على نتيجةٍ مؤكَّدةٍ مُسجَّلةٍ وحدَها — سلوكاً', () {
    // الثابتُ الذي نقضُه هو الشحنُ المزدوجُ بعينِه.
    final unknownCases = <Object>[
      ApiError('boom'),
      TimeoutError(),
      ValidationError('given_id has already been taken', {'given_id': ['x']}),
      ValidationError.messageOnly('given_id has already been taken'),
    ];
    for (final c in unknownCases) {
      final e = moyasarErrorText(c);
      expect(e.resultUnknown, isTrue, reason: '${c.runtimeType} ليست مؤكَّدة');
      expect(e.givenIdConsumed, isFalse,
          reason: 'تجديدُ المعرّفِ على نتيجةٍ مجهولةٍ يُجيزُ شحناً مزدوجاً — '
              '${c.runtimeType}');
    }
    // وما لا تُسجّلُه ميسر لا يُجدِّدُ شيئاً.
    for (final c in <Object>[
      NetworkError(),
      AuthError('x'),
      PaymentCanceledError(),
      UnprocessableTokenError(),
      UnspecifiedError('{}'),
      ValidationError('Amount too low', {'amount': ['x']}),
    ]) {
      expect(moyasarErrorText(c).givenIdConsumed, isFalse,
          reason: 'تجديدٌ بلا سببٍ — ${c.runtimeType}');
    }
    // والمُسجَّلُ المؤكَّدُ وحدَه يُجدِّد: ردُّ 2xx أنشأ مستندَ دفعة.
    // و`PaymentResponse` لا يُبنى في فحصٍ — مُنشِئُه الوحيدُ `fromJson`
    // بوسيطِ `PaymentType` **غيرِ المُصدَّرِ** من الحزمة، وعشرةُ حقولٍ
    // `late` غيرِ قابلةٍ للإغفال. فيُشَدُّ **بنيويّاً**: التجديدُ مُعلَنٌ
    // في فرعٍ واحدٍ لا غير، وهو فرعُ `PaymentResponse`.
    final consumedSites =
        RegExp(r'givenIdConsumed: true').allMatches(rule).toList();
    expect(consumedSites.length, 1,
        reason: 'التجديدُ مُعلَنٌ في ${consumedSites.length} فرعاً — '
            'الحالةُ المؤكَّدةُ الوحيدةُ من الحزمةِ هي ردُّ 2xx');
    final prAt = rule.indexOf('if (result is PaymentResponse) {');
    expect(prAt, greaterThan(-1), reason: 'زالَ فرعُ `PaymentResponse`');
    final prBody = braceBody(rule, prAt);
    expect(prBody.contains('givenIdConsumed: true'), isTrue,
        reason: 'التجديدُ خارجَ فرعِ الدفعةِ المُسجَّلة — '
            'فبلا تجديدٍ هناك تَدورُ العميلةُ في رفضٍ لا مخرجَ منه');
    // والثابتُ بنيويّاً كذلك: لا فرعَ يَجمعُ «مجهولٌ» و«مُستهلَك».
    for (final m in RegExp(r'MoyasarErrorText\(').allMatches(rule)) {
      final blk = parenBlock(rule, m.start);
      final bothFlags =
          blk.contains('resultUnknown: true') && blk.contains('givenIdConsumed: true');
      expect(bothFlags, isFalse,
          reason: 'فرعٌ يُجدّدُ المعرّفَ على نتيجةٍ مجهولة — '
              'وهو الشحنُ المزدوجُ بعينِه: $blk');
    }

    // والشاشةُ تَقرأُ القرارَ ولا تُعيدُ تعدادَ الأنواع.
    final hi = screen.indexOf('_handleNativePayFailure(dynamic result');
    final shared = fnBody(screen, hi);
    expect(shared.contains('e.givenIdConsumed'), isTrue,
        reason: 'الشاشةُ تُجدّدُ بشرطٍ من عندِها — وهكذا كانت تُجدّدُ على '
            '`ApiError` (ردُّ 5xx، نتيجةٌ مجهولة)');
    expect(shared.contains('_mintFreshPendingOrderId'), isTrue,
        reason: 'لا تجديدَ إطلاقاً — فرفضُ البطاقةِ يَصيرُ طريقاً مسدوداً');
    // Google Pay يَقرأُ نظيرَه من الخدمة.
    final g = screen.indexOf('on MoyasarPayFailure catch');
    expect(g, greaterThan(-1));
    final known = screen.substring(g, screen.indexOf('} catch (e, st)', g));
    expect(known.contains('f.recorded'), isTrue,
        reason: 'Google Pay يُجدّدُ بلا شرطٍ أو لا يُجدّدُه أبداً');
    final unknown = screen.substring(screen.indexOf('} catch (e, st)', g));
    final upTo = unknown.indexOf('messenger.showSnackBar');
    expect(upTo, greaterThan(-1));
    expect(unknown.substring(0, upTo).contains('_mintFreshPendingOrderId'),
        isFalse,
        reason: 'تجديدُ المعرّفِ على نتيجةٍ مجهولةٍ يُجيزُ شحناً مزدوجاً');
  });

  test('(٤) والنتيجةُ المجهولةُ تَترُكُ أثراً عندنا — في الثلاثة', () {
    // كان فرعُ Apple/Samsung بلا أيِّ تسجيل: لا `debugPrint` ولا تقرير.
    // ومالٌ قد خُصم بلا طلبٍ مؤكَّدٍ ينقذُه `reconcileOrphanPayments` —
    // فوقوعُه خبرٌ يَلزمُنا، وهو نطاقُ `reportSilent` المُعلَن.
    final hi = screen.indexOf('_handleNativePayFailure(dynamic result');
    final shared = fnBody(screen, hi);
    expect(shared.contains('e.resultUnknown'), isTrue,
        reason: 'الدالّةُ لا تُميّزُ المجهولَ — فلا أثرَ له');
    expect(shared.contains("reason: 'native_pay_unknown_result'"), isTrue,
        reason: 'نتيجةٌ مجهولةٌ على مسارِ مالٍ بلا تقرير');
    expect(shared.contains('debugPrint'), isTrue,
        reason: 'التشخيصُ يُفقَدُ على المسارِ المفهوم');
    // والسببُ **ثابتٌ**: Crashlytics يُجمِّعُ به، فسببٌ متغيّرٌ يُنتجُ
    // مجموعةً لكلِّ جهاز. والمسارُ يُمرَّرُ في `info`.
    expect(RegExp(r"reason: '\$").hasMatch(shared), isFalse,
        reason: 'سببٌ متغيّرٌ — التجميعُ يَضيع');
    expect(shared.contains("'method': method"), isTrue,
        reason: 'لا يُعرَفُ أيُّ مسارٍ أصليٍّ وقعَ فيه');
    final g = screen.indexOf('} catch (e, st)',
        screen.indexOf('on MoyasarPayFailure catch'));
    final gUnknown = screen.substring(g, g + 900);
    expect(gUnknown.contains('google_pay_unknown_result'), isTrue,
        reason: 'المسارُ الثالثُ بلا تقريرٍ عن نتيجةٍ مجهولة');
  });

  group('والخدمةُ لا تُسرّبُ نصَّ البوّابةِ إلى العميلة', () {
    /// الوسيطُ الأوّلُ لكلِّ `MoyasarPayFailure(` — إلى أوّلِ فاصلةٍ في
    /// العمقِ الأعلى، مع احترامِ النصوص.
    List<String> firstArgs() {
      final out = <String>[];
      for (final m in RegExp(r'MoyasarPayFailure\(').allMatches(svc)) {
        final b = parenBlock(svc, m.start);
        final inner = b.substring(b.indexOf('(') + 1, b.length - 1);
        var depth = 0;
        var quote = '';
        for (var i = 0; i < inner.length; i++) {
          final c = inner[i];
          if (quote.isNotEmpty) {
            if (c == r'\') {
              i++;
            } else if (c == quote) {
              quote = '';
            }
            continue;
          }
          if (c == "'" || c == '"') {
            quote = c;
            continue;
          }
          if (c == '(' || c == '[' || c == '{') depth++;
          if (c == ')' || c == ']' || c == '}') depth--;
          if (c == ',' && depth == 0) {
            out.add(inner.substring(0, i).trim());
            break;
          }
        }
        if (out.isEmpty || !b.contains(',')) out.add(inner.trim());
      }
      return out;
    }

    test('كلُّ رسالةٍ عربيّةٌ بلا استقراءٍ من جسمِ ردِّ ميسر', () {
      // **ونعلنُ ما نَستثنيه:** `MoyasarPayFailure(` يُطابِقُ أيضاً
      // **إعلانَ المُنشِئ** (`const MoyasarPayFailure(this.message, …)`)
      // فأوّلُ وسيطِه `this.message` لا رسالة — وهو ما أسقطَ أوّلَ صياغةٍ
      // لهذا الفحص. ووسيطٌ **مُعرِّفٌ** (`message`) مشروعٌ: بُنِيَ من مُبدِّلٍ
      // أعلاه، فالمفحوصُ هو الحروفُ التي تَتدفّقُ إليه.
      final args = firstArgs().where((a) => !a.startsWith('this.')).toList();
      expect(args.length, greaterThanOrEqualTo(3),
          reason: 'الاستخراجُ انهارَ — لا رسائلُ قليلة');
      final literals = <String>[
        ...args.where((a) => a.startsWith("'") || a.startsWith('"')),
      ];
      // ومصدرُ الوسيطِ المُعرِّفِ (`message`): مُبدِّلُ نوعِ خطأِ ميسر
      // ومُهيِّئُه. نَحصُرُ النطاقَ بالمُبدِّلِ نفسِه كي لا تَدخلَ حروفُ
      // الطلبِ (`'SAR'`, `'googlepay'`, الرابط) في المقارنة.
      final sw = svc.indexOf('message = switch (type)');
      expect(sw, greaterThan(-1), reason: 'لم يُوجَد مُبدِّلُ الرسائل');
      final swBlock = svc.substring(sw, svc.indexOf('};', sw));
      // **وكلُّ فرعٍ يَجبُ أن يكونَ حرفاً عربيّاً، لا مجرَّدَ ما نَقدرُ على
      // قراءته.** صياغتي الأولى جمعت الفروعَ بـ`=>\s*('[^']*')` فلم تَرَ
      // فرعاً هو **تعبيرٌ** — ومرَّ اختبارُ قضمٍ أعادَ
      // `error['message']?.toString()` إلى فرعِ `invalid_request_error`
      // **أخضرَ**: أي أنّ الحارسَ كان أعمى عن الصيغةِ التي وُجد لمنعِها.
      final arms = RegExp(r'=>\s*([^,]+),')
          .allMatches(swBlock)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(arms.length, greaterThanOrEqualTo(4),
          reason: 'لم تُقرأ فروعُ المُبدِّل — فالفحصُ أجوف');
      for (final a in arms) {
        // والمسموحُ الوحيدُ غيرَ الحرفِ: `message` نفسُه — فرعُ `_` يَعودُ
        // إلى المُهيِّئِ العربيِّ المفحوصِ أدناه، لا إلى ردِّ البوّابة.
        if (a == 'message') continue;
        expect(a.startsWith("'"), isTrue,
            reason: 'فرعٌ ليس حرفاً عربيّاً ثابتاً — رسالةُ ميسر إنجليزيّةٌ '
                'فلا تُعرَضُ للعميلة: $a');
      }
      literals.addAll(arms.where((a) => a != 'message'));
      final init = RegExp(r"String message = ('[^']*')").firstMatch(svc);
      expect(init, isNotNull, reason: 'لم يُوجَد مُهيِّئُ الرسالة');
      literals.add(init!.group(1)!);
      expect(literals.length, greaterThanOrEqualTo(5),
          reason: 'لم تُجمَع حروفُ الرسائل — فالفحصُ أجوف');
      for (final a in literals) {
        expect(a, matches(RegExp(r'[\u0621-\u064A]')),
            reason: 'رسالةٌ بلا حرفٍ عربيّ: $a');
        expect(a.contains(r'$'), isFalse,
            reason: 'استقراءٌ في رسالةِ العميلة — هكذا وصلَها '
                '«حالة الدفع: failed — Insufficient funds»: $a');
      }
    });

    test('ونصُّ البوّابةِ يَذهبُ إلى `detail` ومنه إلى السجلِّ لا إلى الشاشة',
        () {
      expect(svc, contains('detail:'),
          reason: 'لا حقلَ تشخيصٍ — فإمّا يُعرَضُ النصُّ أو يُفقَدُ كلُّه');
      expect(svc, contains(r"msg=${data['message']"),
          reason: 'رسالةُ ميسر لم تُحفَظْ للتشخيص');
      final g = screen.indexOf('on MoyasarPayFailure catch');
      final known = screen.substring(g, screen.indexOf('} catch (e, st)', g));
      expect(known, contains('debugPrint'),
          reason: 'التشخيصُ لا يُطبَعُ — فالحقلُ زينة');
      expect(RegExp(r'Text\(\s*f\.detail').hasMatch(screen), isFalse,
          reason: 'التشخيصُ يُعرَضُ للعميلة');
    });

    test('والصنفُ يَحملُ القرارَ: `recorded` يُقرَأُ ولا يُفترَض', () {
      expect(svc, contains('final bool recorded'));
      expect(svc, contains('recorded: true'),
          reason: 'لا موضعَ يُعلِنُ أنّ ميسر سجّلت الدفعة — فالتجديدُ لا '
              'يَقعُ أبداً');
      // وغيرُ المُسجَّلِ هو الافتراض: الصمتُ يَجبُ أن يَعني «لم تُسجَّل».
      expect(svc, contains('this.recorded = false'),
          reason: 'افتراضُ `recorded` يَجبُ أن يكون `false` — '
              'التجديدُ عند الشكِّ يُجيزُ شحناً مزدوجاً');
    });
  });
  // ───────────────────────────────────────────────────────────────────────
  // والقاعدةُ نفسُها على شاشتَي SDK — نسختانِ خرجتا على حارسِها
  //
  // «كلُّ فرعٍ في مُبدِّلِ رسائلِ ميسر حرفٌ عربيٌّ ثابتٌ» مقرَّرةٌ أعلاه
  // ومحروسةٌ — في `moyasar_service.dart` وحدَه. وشاشتا SDK كانت لكلٍّ منهما
  // نسختُها، وكلتاهما تُسرِّبُ نصَّ البوّابة. فالقاعدةُ تَسكنُ الآن مرّةً في
  // `lib/utils/moyasar_error_text.dart`، نقيّةً فتُختبَرُ سلوكاً.
  group('خطأُ بوّابةِ ميسر: قاعدةٌ واحدةٌ للشاشتَين', () {
    final String card = stripComments(
        File('lib/screens/moyasar_card_screen.dart').readAsStringSync());
    final String stc = stripComments(
        File('lib/screens/moyasar_stc_screen.dart').readAsStringSync());

    test('سلوكاً: كلُّ رسالةٍ عربيّةٌ ولا نصَّ بوّابةٍ فيها', () {
      // الحالاتُ التي كانت تُسرِّبُ، بنصِّ الحزمة.
      final cases = <Object>[
        ApiError('Invalid API key provided.'),
        ApiError("FormatException: Unexpected character (at character 1)"),
        ValidationError('Amount must be greater than 100', {'amount': 'x'}),
        NetworkError(),
        TimeoutError(),
        AuthError('Unauthorized'),
        PaymentCanceledError(),
        UnprocessableTokenError(),
        UnspecifiedError('{"html":"<body>502 Bad Gateway</body>"}'),
      ];
      for (final c in cases) {
        final e = moyasarErrorText(c);
        expect(e.message.trim(), isNotEmpty);
        expect(RegExp(r'[ء-ي]').hasMatch(e.message), isTrue,
            reason: 'رسالةٌ بلا حرفٍ عربيٍّ عن ${c.runtimeType}');
        expect(RegExp('[A-Za-z]{4,}').hasMatch(e.message), isFalse,
            reason: 'نصُّ البوّابةِ وصلَ العميلةَ عن ${c.runtimeType}: '
                '${e.message}');
        // والتشخيصُ لا يُفقَد.
        expect(e.detail.trim(), isNotEmpty, reason: '${c.runtimeType} بلا تشخيص');
      }
    });

    test('«لا نعرف» للمهلةِ ولـ`ApiError` — ولا دعوةَ إعادةٍ معها', () {
      // ودجةُ البطاقةِ تُحوّلُ استثناءاتِها إلى `ApiError(e.toString())`،
      // فقد يَكونُ الخصمُ تمّ وفشلَ تحليلُ الرد — ولا يُفرَّقُ من النوع.
      for (final c in <Object>[TimeoutError(), ApiError('boom')]) {
        final e = moyasarErrorText(c);
        expect(e.resultUnknown, isTrue, reason: '${c.runtimeType} ليست «فشلاً»');
        expect(e.message.contains('قد خُصم'), isTrue);
        expect(e.message.contains('لا تُعيدي الدفع'), isTrue,
            reason: 'دعوةُ الإعادةِ على نتيجةٍ مجهولةٍ تُنتجُ شحناً مزدوجاً');
      }
      // وما لم يَصِلِ الطلبُ أصلاً ليس مجهولاً.
      expect(moyasarErrorText(NetworkError()).resultUnknown, isFalse);
      // والإلغاءُ ليس فشلاً.
      expect(moyasarErrorText(PaymentCanceledError()).message.contains('فشل'),
          isFalse);
    });

    test('`description` لا يُعرَضُ — فهو الوصفُ الذي أرسلناه', () {
      expect(rule.contains('result.description'), isTrue,
          reason: 'يُقرَأُ للتشخيصِ وحدَه');
      // ولا يُعادُ رسالةً: الوصفُ يَظهرُ في `detail` فقط.
      final retBodies = RegExp(r'MoyasarErrorText\(\s*([^,)]+)')
          .allMatches(rule)
          .map((m) => m.group(1)!.trim())
          .where((a) => !a.startsWith('this.'))
          .toList();
      expect(retBodies.length, greaterThanOrEqualTo(8),
          reason: 'الاستخراجُ انهارَ — فالفحصُ أجوف');
      for (final a in retBodies) {
        final ok = a.startsWith("'") ||
            a == 'kMoyasarUnknownResult' ||
            a.startsWith('declined');
        expect(ok, isTrue, reason: 'رسالةٌ ليست حرفاً ثابتاً: $a');
      }
      // والشاشتانِ لا تَحملانِ نسخةً من المُبدِّل.
      for (final src in [card, stc]) {
        expect(src.contains('result.description'), isFalse,
            reason: 'عادَ عرضُ الوصفِ الذي أرسلناه');
        expect(RegExp(r'onFailure\(\s*result\.message').hasMatch(src), isFalse,
            reason: 'عادَ تسريبُ رسالةِ البوّابة');
        expect(src.contains('moyasarErrorText('), isTrue,
            reason: 'الشاشةُ لا تُنادي القاعدة');
      }
    });

    test('نداءا الحزمةِ داخلَ try — وإلّا حُبِست العميلةُ في شاشةِ STC', () {
      // `Moyasar.pay`/`verifyOTP` يَفعلانِ `jsonDecode(res.body)` بلا حماية
      // ثمّ `String errorType = jsonBody['type']`، و`onSubmit` في الشاشةِ
      // `VoidCallback` فالمستقبلُ غيرُ مُنتظَر: الرميُ خطأٌ غيرُ مُعالَجٍ
      // يُبقي `_isSubmitting` صحيحاً، و`PopScope(canPop: !_isSubmitting)`
      // يُقفِلُ الرجوع — فلا مخرجَ إلّا قتلُ التطبيق.
      for (final call in const ['Moyasar.pay(', 'Moyasar.verifyOTP(']) {
        final at = stc.indexOf(call);
        expect(at, greaterThan(-1), reason: 'زالَ النداء: $call');
        final tryAt = stc.lastIndexOf('try {', at);
        expect(tryAt, greaterThan(-1), reason: '$call بلا try');
        expect(stc.substring(tryAt, at).contains('}'), isFalse,
            reason: '`try` أقربُ منه كتلةٌ أخرى — $call ما زال عارياً');
      }
      expect(stc.contains('canPop: !_isSubmitting'), isTrue,
          reason: 'لو زالَ القفلُ فالتعليلُ يُراجَعُ لا يُسكَت');
      expect(RegExp(r'catch \(e\) \{').allMatches(stc).length,
          greaterThanOrEqualTo(2));
      expect(stc.contains("debugPrint('[stc] initiate threw:"), isTrue);
      expect(stc.contains("debugPrint('[stc] verifyOTP threw:"), isTrue);
    });

    test('ورميُ طورِ الرمزِ يَقولُ «لا نعرف» لا «فشل»', () {
      final at = stc.indexOf("debugPrint('[stc] verifyOTP threw:");
      expect(at, greaterThan(-1));
      final blk = stc.substring(at, (at + 600).clamp(0, stc.length));
      expect(blk.contains('قد خُصم'), isTrue,
          reason: 'لا تَقُلْ «فشل» عن نتيجةٍ مجهولة');
      expect(blk.contains('لا تُعيدي الدفع'), isTrue,
          reason: 'دعوةُ الإعادةِ هنا تُنتجُ شحناً مزدوجاً');
      expect(blk.contains('فشل'), isFalse,
          reason: 'دعوى فشلٍ عن دفعةٍ قد تَكونُ تمّت');
    });

    test('طورُ الرمزِ لا يُفتَحُ بلا رابطِ تحقّق', () {
      // `transactionUrl` في الحزمةِ `String?`، والتحويلُ `as` غيرُ مفحوص.
      expect(stc.contains('src is StcResponseSource'), isTrue,
          reason: 'تحويلٌ غيرُ مفحوصٍ يَرمي على شكلٍ آخر');
      expect(stc.contains('result.source as StcResponseSource'), isFalse,
          reason: 'عادَ التحويلُ غيرُ المفحوص');
      final u = stc.indexOf('if (url.isEmpty)');
      expect(u, greaterThan(-1), reason: 'لا حارسَ لرابطٍ غائب');
      final ph = stc.indexOf('_phase = _Phase.otp');
      expect(u, lessThan(ph),
          reason: 'الحارسُ بعدَ الانتقالِ لا يَمنعُ شيئاً — الترتيبُ هو الإصلاح');
      expect(stc.contains('لم يُخصم أي مبلغ'), isTrue);
    });
  });


}
