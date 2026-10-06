import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/low_rating.dart';
import 'helpers/strip_comments.dart';

/// **ما تَجمعُه العميلةُ عن خدمةٍ سيّئة، ومَن يَراه.**
///
/// حوارُ التقييمِ يَجمعُ أربعةَ أشياء: نجوماً، وسبباً من قائمة، و**نصّاً
/// تَكتبُه**، و**صورةً من الكاميرا** تُرفَعُ إلى `order_feedback/` — تُسمّيها
/// `storage.rules` «إثباتاً ميدانيّاً لا يُستبدَل ولا يُحذَف». واثنانِ منها لم
/// يَكن لهما قارئٌ في أيِّ سطح: `rating_evidence_url` **كتابةٌ واحدةٌ وصفرُ
/// قراءة**، و`rating_comment` يُقرَأُ **شرطاً لا عرضاً**. فالمالكُ يُنبَّهُ عن
/// تقييمِ نجمةٍ ثمّ لا يَجدُ شكواها ولا صورتَها، والصورةُ تُخزَّنُ ويُدفَعُ
/// ثمنُها لتُقرَأَ أبداً.
///
/// والقاعدةُ المشدودةُ هنا **عامّةٌ لا حالةٌ**: كلُّ حقلٍ يَكتبُه
/// `submitOrderRating` يَجبُ أن يَكونَ له **قارئٌ باسمِه** في `low_rating.dart`
/// وأن يُنادى ذلك القارئُ في سطحٍ إداريّ. فحقلٌ خامسٌ يُجمَعُ غداً ولا يُعرَضُ
/// يَسقطُ الفحصَ يومَ كتابتِه لا بعدَ سنة.
void main() {
  String read(String p) => File(p).readAsStringSync();
  final insights = read('lib/screens/admin/admin_insights_screen.dart');
  final rule = read('lib/utils/low_rating.dart');
  final svc = read('lib/services/order_service.dart');

  /// جسمُ دالّةٍ بموازنةِ الأقواسِ المعقوفةِ **بعدَ** قائمةِ المعامَلات.
  ///
  /// **ولماذا لا `substring(i)` إلى آخرِ الملفّ:** صياغتي الأولى فحصت
  /// `InkWell` و`errorBuilder` في الملفِّ كلِّه من موضعِ الدالّة، فمرَّ
  /// اختبارا قضمٍ **أخضرَ**: الشاشةُ تَحملُ `InkWell` في بطاقاتٍ أخرى،
  /// و`errorBuilder` ثانياً في عارضِ الصورةِ الكامل. فحذفُ أحدِهما من
  /// البطاقةِ لا يُسقِطُ شيئاً — وهو فخُّ الحدِّ غيرِ المُوازَنِ نفسُه.
  String body(String src, String sig) {
    final i = src.indexOf(sig);
    expect(i, greaterThan(-1), reason: 'لم تُوجَد $sig');
    var j = src.indexOf('(', i);
    var depth = 0;
    for (; j < src.length; j++) {
      if (src[j] == '(') depth++;
      if (src[j] == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    final open = src.indexOf('{', j);
    depth = 0;
    for (var k = open; k < src.length; k++) {
      if (src[k] == '{') depth++;
      if (src[k] == '}') {
        depth--;
        if (depth == 0) return src.substring(open, k + 1);
      }
    }
    fail('تعذّرَ اقتطاعُ جسمِ $sig');
  }

  group('القاعدةُ: لا تقييمَ مُلفَّق', () {
    test('غيابُ الحقلِ أو فراغُه أو غيرُ الرقميِّ = لا نعرف', () {
      for (final v in [null, '', '  ', 'ممتاز', {}, []]) {
        expect(orderRatingOf({'rating': v}), isNull, reason: '$v');
        expect(orderIsLowRated({'rating': v}), isFalse, reason: '$v');
      }
      expect(orderRatingOf(<String, dynamic>{}), isNull);
      expect(orderIsLowRated(<String, dynamic>{}), isFalse,
          reason: 'طلبٌ لم يُقيَّم كان يُقرأُ 5.0 — افتراضٌ مُلفَّق');
    });

    test('وما خرجَ عن [1,5] لا تقييمٌ — نافذةُ الخادمِ نفسُها', () {
      for (final v in [0, 0.0, -1, 6, 99, 5.01]) {
        expect(orderRatingOf({'rating': v}), isNull, reason: '$v');
      }
      for (final v in [1, 1.0, 2, 2.5, 5, 5.0]) {
        expect(orderRatingOf({'rating': v}), isNotNull, reason: '$v');
      }
    });

    test('العتبةُ عتبةُ التنبيهِ الخادميّ: ≤2 منخفضٌ و>2 لا', () {
      expect(orderIsLowRated({'rating': 1}), isTrue);
      expect(orderIsLowRated({'rating': 2}), isTrue);
      expect(orderIsLowRated({'rating': 2.0}), isTrue);
      expect(orderIsLowRated({'rating': 2.5}), isFalse);
      expect(orderIsLowRated({'rating': 3}), isFalse);
      expect(orderIsLowRated({'rating': '1'}), isTrue, reason: 'نصٌّ رقميّ');
      expect(kLowRatingMax, 2.0);
    });

    test('«1» لا «1.0»', () {
      expect(ratingLabel(1), '1');
      expect(ratingLabel(2.0), '2');
      expect(ratingLabel(1.5), '1.5');
    });
  });

  group('القاعدةُ: الإثباتُ وشكلُه', () {
    test('نصٌّ فراغٌ ليس تعليقاً — وهو ما كان يَمُرُّ من `!= null`', () {
      expect(ratingCommentOf({'rating_comment': '   '}), isNull);
      expect(ratingCommentOf({'rating_comment': ''}), isNull);
      expect(ratingCommentOf({'rating_comment': ' تأخّروا ساعتين '}),
          'تأخّروا ساعتين');
      expect(ratingReasonOf({'rating_reason': 'تأخير'}), 'تأخير');
      expect(ratingReasonOf(<String, dynamic>{}), isNull);
    });

    test('الرابطُ `https` وحدَه — غيرُه يَرمي داخلَ Image.network في build',
        () {
      expect(ratingEvidenceUrlOf({'rating_evidence_url': 'x.jpg'}), isNull);
      expect(ratingEvidenceUrlOf({'rating_evidence_url': 'http://a/b.jpg'}),
          isNull);
      expect(ratingEvidenceUrlOf({'rating_evidence_url': ''}), isNull);
      expect(ratingEvidenceUrlOf(<String, dynamic>{}), isNull);
      const ok = 'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media';
      expect(ratingEvidenceUrlOf({'rating_evidence_url': ok}), ok);
    });
  });

  group('والسطحُ يَعرِضُ ما يُجمَع', () {
    /// جسمُ معامَلةِ `submitOrderRating` بموازنةِ الأقواس — `indexOf('}')`
    /// يَقفُ عند أوّلِ `}` وهو فخٌّ مسجَّلٌ في هذا المستودعِ سِتَّ مرّات.
    Set<String> writtenFields() {
      // **لا أوّلَ ورودٍ لشكلٍ مشترَك.** `transaction.update(orderRef, {`
      // ترِدُ أيضاً في معامَلةِ **الإلغاءِ** أعلى الملفّ، فأوّلُ ورودٍ يُعطي
      // `status`/`cancelled_at`/`needs_refund` — وقد حدثَ: الفحصُ أبلغَ عن
      // خمسةِ حقولٍ «بلا قارئ» لا علاقةَ لها بالتقييم. فالمِرساةُ حقلُ
      // التقييمِ نفسُه ثمّ رجوعٌ إلى الوراء.
      final marker = svc.indexOf("'rating_evidence_url':");
      expect(marker, greaterThan(-1), reason: 'لم تُوجَد كتابةُ الإثبات');
      final i = svc.lastIndexOf('transaction.update(orderRef, {', marker);
      expect(i, greaterThan(-1), reason: 'لم تُوجَد كتابةُ التقييم');
      final open = svc.indexOf('{', i);
      var depth = 0;
      var close = -1;
      for (var k = open; k < svc.length; k++) {
        if (svc[k] == '{') depth++;
        if (svc[k] == '}') {
          depth--;
          if (depth == 0) {
            close = k;
            break;
          }
        }
      }
      expect(close, greaterThan(open), reason: 'تعذّرَ اقتطاعُ جسمِ الكتابة');
      return RegExp(r"""'([a-z_]+)'\s*:""")
          .allMatches(svc.substring(open, close))
          .map((m) => m.group(1)!)
          .toSet();
    }

    /// حقلٌ ← قارئُه باسمِه في القاعدة. و`rated_at` مستثنىً بسببٍ مكتوب:
    /// طابعٌ زمنيٌّ خادميٌّ لمنعِ التكرارِ ولتجميعِ الخادم، لا محتوًى تَكتبُه
    /// العميلةُ ليُقرَأ.
    const readers = {
      'rating': 'orderRatingOf',
      'rating_comment': 'ratingCommentOf',
      'rating_reason': 'ratingReasonOf',
      'rating_evidence_url': 'ratingEvidenceUrlOf',
    };
    const exempt = {'rated_at'};

    test('كلُّ حقلٍ مكتوبٍ له قارئٌ باسمِه — لا حقلَ يُجمَعُ ويُطرَح', () {
      final written = writtenFields();
      expect(written.length, greaterThanOrEqualTo(5),
          reason: 'الاقتطاعُ انهارَ — لا جسمٌ قصير');
      final orphans = written
          .where((f) => !readers.containsKey(f) && !exempt.contains(f))
          .toList();
      expect(orphans, isEmpty,
          reason: '\n\nحقلٌ يُجمَعُ من العميلةِ ولا قارئَ له:\n  • '
              '${orphans.join('\n  • ')}\n');
      // والاتجاهُ الآخر: قارئٌ لحقلٍ لم يَعُد يُكتَبُ = قائمةٌ تَتعفّن.
      expect(readers.keys.toSet().difference(written), isEmpty,
          reason: 'قارئٌ لحقلٍ لم يَعُد يُكتَب');
    });

    test('وكلُّ قارئٍ مُعرَّفٌ في القاعدةِ ومُنادًى في سطحٍ إداريّ', () {
      final code = stripComments(insights);
      for (final fn in readers.values) {
        expect(rule, contains('$fn('), reason: 'القاعدةُ لا تُعرِّف $fn');
        expect(code, contains('$fn('),
            reason: 'حارسُ السمعةِ لا يُنادي $fn — فالحقلُ مجموعٌ ولا يُعرَض');
      }
    });

    test('ونصُّ شكواها وصورتُها مُصيَّرانِ فعلاً لا مُقرَأَينِ فحسب', () {
      final tile = body(stripComments(insights),
          'Widget _buildLowRatingTile(DocumentSnapshot');
      expect(tile.length, greaterThan(500),
          reason: 'الاقتطاعُ انهارَ — لا جسمٌ قصير');
      expect(tile, contains('Text(comment'),
          reason: 'كلماتُها تُقرَأُ ولا تُعرَض — شرطٌ لا عرضٌ، وهو العطلُ عينُه');
      expect(tile, matches(RegExp(r'Image\.network\(\s*evidence')),
          reason: 'الصورةُ تُقرَأُ ولا تُعرَض');
      expect(tile, contains('errorBuilder'),
          reason: 'صورةٌ تَفشلُ تُقرَأُ «لا صورة» — فشلٌ صامتٌ في مكانِ إثبات');
      expect(tile, contains('loadingBuilder'),
          reason: 'بلا حالةِ تحميلٍ تُقرَأُ الفجوةُ «لا صورة»');
    });

    test('والعرضُ الكاملُ للصورةِ موجودٌ ويَقولُ فشلَه هو أيضاً', () {
      // المُصغَّرةُ بحجمِ ١١٠ لا تُثبِتُ شيئاً، والعارضُ له `errorBuilder`
      // خاصٌّ به — وفحصٌ غيرُ مُنطاقٍ كان يَقنعُ بوجودِ أحدِهما فيُمَرَّرُ
      // حذفُ الآخر (أُثبِتَ باختبارِ قضم).
      final viewer = body(stripComments(insights), 'void _openEvidence(');
      expect(viewer, contains('InteractiveViewer'),
          reason: 'لا عرضَ كاملاً للصورة');
      expect(viewer, contains('errorBuilder'),
          reason: 'العارضُ الكاملُ يَبقى أسودَ فارغاً على الفشل');
    });

    test('والسهمُ صارَ نقرةً تَفتحُ الطلب — لم يَكن زرّاً أصلاً', () {
      final tile = body(stripComments(insights),
          'Widget _buildLowRatingTile(DocumentSnapshot');
      expect(tile.contains('InkWell'), isTrue,
          reason: 'البطاقةُ تَحملُ سهماً أماميّاً ولا تَستجيبُ للنقر');
      expect(tile.contains('AdminOrderDetailsScreen(orderId: doc.id)'), isTrue,
          reason: 'النقرُ لا يَفتحُ الطلبَ الذي تَشكو منه');
    });

    test('ولا افتراضَ 5.0 باقياً في حارسِ السمعة', () {
      final code = stripComments(insights);
      expect(code.contains("data['rating'] ?? 5.0"), isFalse,
          reason: 'عادَ التقييمُ المُلفَّق');
      // وشرطُ التعليقِ باقٍ كما هو — قرارٌ مسجَّلٌ يَشدُّه
      // `driver_rating_claim_test` كذلك، وتغييرُه قرارُ المالك.
      expect(code, contains("data['rating_comment'] != null"));
    });

    test('والمقطوعُ من القائمةِ يُقالُ عددُه', () {
      final code = stripComments(insights);
      expect(code, contains('lowRatings.length > 3'),
          reason: 'ثلاثةٌ تُعرَضُ والبقيّةُ تَغيبُ بلا أثر');
    });
  });

  test('والمصطلحاتُ ما زالت في الخامِّ — مضادَّةُ فرطِ الحجب', () {
    for (final t in ["data['rating'] ?? 5.0", 'rating_evidence_url']) {
      expect(insights + rule + svc, contains(t),
          reason: 'زالَ شرحُ القرارِ، فالفحوصُ أعلاه لا تَحرُسُ شيئاً مفهوماً');
    }
  });
}
