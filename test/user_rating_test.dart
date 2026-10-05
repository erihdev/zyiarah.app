// حارس: **لا تقييمَ مُلفَّقاً.** غيابُ التقييم يُعرض «—»، لا رقماً اخترعناه.
//
// وُجد بتشغيل التطبيق بحسابٍ حقيقيّ (2026-10-04): بطاقةُ «تقييمك» في الملفّ
// الشخصيّ تعرض «4.9 ★». والرقمُ مكتوبٌ في الشيفرة: `_currentUser?.rating ?? 4.9`
// فوق نموذجٍ افتراضُه `4.9` أيضاً — طبقتان من الاختلاق.
//
// ولا شيءَ في المشروع يكتب `rating` على مستند مستخدم: `aggregateDriverRating`
// في `functions/index.js` يكتب `rating_avg` و`rating_count` على مجموعة
// **`drivers`** وحدها. فكلُّ عميلةٍ كانت ترى 4.9 وتظنُّها تقييمَها.
//
// والبطاقةُ المجاورة لها تفعل الصواب أصلاً: «إجمالي الحجوزات» تعرض «—» حين
// يتعذّر العدّ. فالصيغةُ كانت حاضرةً بجانبها.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/user_model.dart';

void main() {
  group('نموذجُ المستخدم: غيابُ التقييم ليس 4.9', () {
    ZyiarahUser parse(Map<String, dynamic> m) => ZyiarahUser.fromMap('u1', m);

    test('مستندٌ بلا rating ⇒ null', () {
      expect(parse({'name': 'س'}).rating, isNull);
    });

    test('مستندٌ برقمٍ حقيقيّ ⇒ الرقم كما هو', () {
      expect(parse({'rating': 4.2}).rating, 4.2);
      expect(parse({'rating': 5}).rating, 5.0);
      // صفرٌ تقييمٌ لا غياب — لا يُبدَّل بافتراض.
      expect(parse({'rating': 0}).rating, 0.0);
    });

    test('قيمةٌ تالفة ⇒ لا انهيار ولا 4.9 مُخترعة', () {
      expect(parse({'rating': 'ليس رقماً'}).rating, 0.0);
    });

    test('البانية بلا تقييم ⇒ null', () {
      final u = ZyiarahUser(
          uid: 'u', name: 'س', email: 'a@b.c', phone: '5', role: 'client');
      expect(u.rating, isNull);
    });
  });

  group('الشاشة لا تخترع رقماً', () {
    final src = File('lib/screens/profile_screen.dart').readAsStringSync();

    test('لا احتياطَ ثابتاً للتقييم', () {
      expect(src.contains('?? 4.9'), isFalse,
          reason: 'عاد الرقمُ المخترَع — كلُّ عميلةٍ ترى تقييماً لم يحسبه أحد');
    });

    test('بلا تقييمٍ تُعرض شَرطةُ الغياب', () {
      expect(src.contains("rating == null"), isTrue);
      expect(src.contains("'—'"), isTrue);
    });

    test('النجمةُ تتبع رقماً لا شَرطة', () {
      expect(src.contains("rating == null ? ratingText : '\$ratingText ★'"),
          isTrue,
          reason: '«— ★» تقرأ كعطلٍ لا كغياب');
    });
  });

  group('النموذجُ لا يُعيد الاختلاق من جهةٍ أخرى', () {
    final src = File('lib/models/user_model.dart').readAsStringSync();

    test('لا 4.9 في النموذج إطلاقاً', () {
      // كانت في موضعين: البانية و fromMap. أيُّ عودةٍ تُعيد العطل.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//') &&
              !l.trimLeft().startsWith('///'))
          .join('\n');
      expect(code.contains('4.9'), isFalse,
          reason: 'عاد الافتراضُ الثابت إلى النموذج');
    });

    test('الحقلُ قابلٌ للغياب', () {
      expect(src.contains('final double? rating;'), isTrue);
    });
  });

  group('نقاط قطرات: لا رقمَ قبل أن نعرفه', () {
    // نفسُ عائلة «تقييمك 4.9»، وُجدت في التشغيل الحيّ نفسِه بعد ساعات:
    // شريطُ «ينقصكِ كذا» يحسب `50 - _qatratPoints` و`_qatratPoints` صفرٌ
    // أثناء التحميل — فيقول «50 نقطة» لمن تملك 48 وينقصها اثنتان، ثمّ يقفز
    // إلى «2 نقطة» حين يصل الرصيد. والعدّادُ فوقه مباشرةً يعرض هيكلَ تحميلٍ
    // في الحال نفسِها: الصيغةُ الصحيحة كانت بجانب الخطأ، كما كانت «إجمالي
    // الحجوزات» بجانب «تقييمك».
    final src = File('lib/screens/profile_screen.dart').readAsStringSync();

    test('الشريطُ يفحص `_walletLoaded` لا الخطأَ وحده', () {
      expect(src.contains("_walletError || !_walletLoaded\n                                ? '—'"),
          isTrue,
          reason: 'عاد الشريطُ يحسب رقماً من رصيدٍ لم يصل');
    });

    test('والاستبدالُ لا يُفتح قبل معرفة الرصيد', () {
      expect(
          src.contains(
              'final canRedeem = !_walletError && _walletLoaded && _qatratPoints >= 50;'),
          isTrue);
    });

    test('العدّادُ فوقه ما زال يُشَمّر أثناء التحميل (مرجعُ الصيغة)', () {
      expect(src.contains("key: ValueKey('qshimmer')"), isTrue);
    });
  });

  group('تقييمُ السائق في شاشة التتبّع: لا نجمةَ بلا تقييم', () {
    // العضوُ الثالث في العائلة، وأسوأُها: `data['driver_rating_avg'] ?? 5.0`
    // — و**لا شيءَ في المستودع كان يكتب هذا الحقل إطلاقاً**. فالرقمُ مختلَقٌ
    // دائماً لا أحياناً: كلُّ عميلةٍ تتتبّع طلبَها ترى «★ 5.0» لسائقها.
    // (`aggregateDriverRating` يكتب `rating_avg` على مجموعة `drivers`، وقاعدةُ
    // `drivers` تمنع العميلَ من قراءتها — فلا سبيلَ للشاشة إليها مباشرةً.)
    final src =
        File('lib/screens/order_tracking_screen.dart').readAsStringSync();

    test('لا احتياطَ ثابتاً', () {
      // الشيفرةُ تشرح القرارَ بذكر `?? 5.0` في تعليقها، فالفحصُ بلا حجبٍ
      // يفشل على توثيقه هو — وقع ذلك فعلاً. نحجب أسطرَ التعليق ثمّ **نؤكّد
      // أنّ العبارةَ ما زالت في النصّ الخام**، فالحجبُ المفرِط لا يُفرّغ
      // الفحص. (درسُ حارسِ تمارا ونشرِ الدوالّ.)
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('?? 5.0'), isFalse,
          reason: 'عاد التقييمُ المخترَع لكلّ سائق');
      expect(src.contains('?? 5.0'), isTrue,
          reason: 'اختفى التعليقُ الشارح — الحجبُ بلا موضوع');
    });

    test('والنجمةُ مشروطةٌ بوجود رقمٍ حقيقيّ', () {
      expect(src.contains('if (_ratingOf(data) != null)'), isTrue);
      expect(src.contains('static double? _ratingOf('), isTrue);
    });

    test('وصفرٌ أو قيمةٌ تالفة = لا تقييم', () {
      final i = src.indexOf('static double? _ratingOf(');
      final body = src.substring(i, src.indexOf('\n  }\n', i));
      expect(body.contains('d <= 0'), isTrue);
      expect(body.contains('!d.isFinite'), isTrue);
    });

    test('والخادمُ يختمه عند الإسناد من مستند السائق', () {
      final fn = File('functions/index.js').readAsStringSync();
      final n = 'driver_rating_avg: Number(d.rating_avg)'.allMatches(fn).length;
      expect(n, 2,
          reason: 'موضعا الإسناد كلاهما يختم التقييم — واحدٌ فقط يترك نصفَ '
              'الطلبات بلا نجمة');
      expect(fn.contains('Number.isFinite(Number(d.rating_avg)) && Number(d.rating_avg) > 0'),
          isTrue,
          reason: 'سائقٌ بلا تقييمٍ بعد يجب ألّا يُختم بصفر');
    });
  });
}
