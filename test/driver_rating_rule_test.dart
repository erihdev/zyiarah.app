import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/driver_rating.dart';

/// القاعدةُ نفسُها قيميّاً — و«صفرُ العدّادِ غيابٌ لا صفر».
///
/// شرحُ العطلِ ونطاقُه في `test/driver_rating_claim_test.dart`.
void main() {
  group('العدّادُ هو الفاصل', () {
    test('بلا عدّادٍ لا تقييم — ولو حَملَ المستندُ بذرَ ٥٫٠', () {
      expect(driverRatingOf(5.0, 0), isNull);
      expect(driverRatingOf(5.0, null), isNull);
      expect(driverRatingLabel(5.0, 0), kNoRatingLabel);
      expect(driverIsRated(5.0, 0), isFalse);
    });

    test('ومع عدّادٍ موجبٍ يُقرأُ المتوسّط', () {
      expect(driverRatingOf(4.2, 3), 4.2);
      expect(driverRatingLabel(4.2, 3), '4.2');
      expect(driverIsRated(4.2, 3), isTrue);
    });

    test('ومتوسّطٌ قيمتُه صفرٌ **تقييمٌ** لا غياب', () {
      // عميلاتٌ قيّمن بأدنى درجةٍ ⇒ متوسّطٌ منخفضٌ جدّاً. الغيابُ هو العدّادُ
      // لا القيمة — وهو عينُ تمييزِ `amounts.js`: «الصفرُ قرارٌ لا غياب».
      expect(driverRatingOf(0, 5), 0);
      expect(driverRatingLabel(0, 5), '0.0');
      expect(driverIsRated(0, 5), isTrue);
    });

    test('وعدّادٌ سالبٌ (بياناتٌ تالفة) يُقرأُ غياباً لا تقييماً', () {
      expect(driverRatingOf(4.9, -1), isNull);
    });
  });

  group('القيمُ النصّيّةُ تُقرأ', () {
    // حقولُ المستنداتِ القديمةِ قد تُخزَّن نصّاً — وشاشةُ الأداءِ تَحرسُ من
    // ذلك صراحةً («الضربُ المباشرُ في الفرزِ ينهار»).
    test('نصُّ المتوسّطِ ونصُّ العدّادِ', () {
      expect(driverRatingOf('4.5', '2'), 4.5);
      expect(driverRatingLabel('4.5', '2'), '4.5');
      expect(driverRatingOf('4.5', '0'), isNull);
    });

    test('ونصٌّ غيرُ رقميٍّ مع عدّادٍ موجبٍ ⇒ غياب', () {
      // عدّادٌ موجبٌ ومتوسّطٌ تالفٌ: لا رقمَ نَثقُ به، فـ«—» أصدقُ من اختلاق.
      expect(driverRatingOf('abc', 3), isNull);
      expect(driverRatingLabel('abc', 3), kNoRatingLabel);
    });

    test('وغيابُ الحقلَين معاً', () {
      expect(driverRatingOf(null, null), isNull);
      expect(driverRatingLabel(null, null), kNoRatingLabel);
    });
  });

  test('ونصُّ الغيابِ هو نفسُه المستعمَلُ في بقيّةِ الواجهات', () {
    expect(kNoRatingLabel, '—');
  });
}
