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

  test('(١) الثلاثةُ تَقولُ «قد خُصم» ولا تَدّعي الفشلَ على نتيجةٍ مجهولة', () {
    expect(unknownMark.isNotEmpty, isTrue);
    final count = unknownMark.allMatches(screen).length;
    expect(count, greaterThanOrEqualTo(3),
        reason: 'الجملةُ في $count موضعٍ من ثلاثة — مسارٌ أصليٌّ يَدّعي '
            'الفشلَ على نتيجةٍ مجهولة');
  });

  test(
      '(٢) ولكلِّ مسارٍ فرعُه: NetworkError في الاثنَين، و`catch` عامٌّ '
      'في Google Pay', () {
    for (final fn in ['_onApplePayResult', '_onSamsungPayResult']) {
      final i = screen.indexOf(fn);
      expect(i, greaterThan(-1), reason: 'لم يُوجَد $fn');
      final body = screen.substring(i, i + 2200);
      expect(body, contains('result is NetworkError'),
          reason: '$fn بلا فرعِ انقطاعٍ — فانقطاعُ الشبكةِ يُقرأُ فشلَ دفع');
      expect(body, contains(unknownMark), reason: '$fn يَدّعي الفشل');
    }
    final g = screen.indexOf('onPaymentResult: (result) async {');
    expect(g, greaterThan(-1), reason: 'لم يُوجَد مُعالِجُ Google Pay');
    final gpay = screen.substring(g, g + 2600);
    expect(gpay, contains('on MoyasarPayFailure catch'),
        reason: 'Google Pay لا يُميّزُ الفشلَ المفهومَ من المجهول');
    expect(gpay, contains(unknownMark),
        reason: 'المسارُ المجهولُ في Google Pay يَدّعي الفشل');
    expect(gpay, contains('google_pay_unknown_result'),
        reason: 'نتيجةٌ مجهولةٌ على مسارِ مالٍ بلا أثرٍ عندنا — '
            'قاعدةُ `reportSilent`');
  });

  test('(٣) وتجديدُ المعرّفِ على فشلٍ مُسجَّلٍ وحدَه — في الثلاثة', () {
    // Apple/Samsung: `ApiError || PaymentResponse` = سجّلته ميسر.
    // Google Pay: `recorded` من `MoyasarPayFailure`.
    final mints = RegExp(r'_mintFreshPendingOrderId').allMatches(screen).length;
    expect(mints, greaterThanOrEqualTo(4),
        reason: 'مواضعُ التجديدِ $mints — المسارُ الثالثُ بلا تجديدٍ يُعيدُ '
            'المحاولةَ بمعرّفٍ مُستهلَكٍ فتُعادُ الدفعةُ الفاشلةُ نفسُها');
    final g = screen.indexOf('on MoyasarPayFailure catch');
    expect(g, greaterThan(-1));
    final known = screen.substring(g, screen.indexOf('} catch (e, st)', g));
    expect(known, contains('f.recorded'),
        reason: 'Google Pay يُجدّدُ المعرّفَ بلا شرطٍ أو لا يُجدّدُه أبداً');
    final unknown = screen.substring(screen.indexOf('} catch (e, st)', g));
    final nextBrace = unknown.indexOf('messenger.showSnackBar');
    expect(nextBrace, greaterThan(-1));
    expect(unknown.substring(0, nextBrace).contains('_mintFreshPendingOrderId'),
        isFalse,
        reason: 'تجديدُ المعرّفِ على نتيجةٍ مجهولةٍ يُجيزُ شحناً مزدوجاً');
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
    final String rule =
        stripComments(File('lib/utils/moyasar_error_text.dart').readAsStringSync());
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
