// زرُّ دفعٍ على إعدادٍ نائبٍ لا يَقبضُ شيئاً — والقاعدةُ كانت في سطحٍ من اثنَين.
//
// حارسُ Samsung Pay كان صحيحاً (`isEmpty || startsWith('REPLACE')` ⇒ إخفاء)،
// وزرُّ Google Pay على بُعدِ تسعينَ سطراً فوقَه كان مشروطاً بـ
// `_googlePayConfigFuture != null` وهو **صحيحٌ دائماً** على أندرويد. والأصلُ
// المشحونُ يَحملُ `environment: TEST` ومفتاحَ ميسر التجريبيَّ ومُعرِّفَ تاجرٍ
// يَبدأُ بـ`REPLACE` حرفيّاً — أي عينَ ما يَفحصُه حارسُ Samsung.
//
// فالقاعدةُ في `lib/utils/native_pay_config.dart`، ويُنادِيها السطحانِ معاً.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/native_pay_config.dart';

import 'helpers/strip_comments.dart';

String _screen() =>
    File('lib/screens/payment_summary_screen.dart').readAsStringSync();

/// جسمُ دالّةٍ بموازنةِ الأقواس، بعدَ موازنةِ قائمةِ المعامَلاتِ أوّلاً —
/// فأوّلُ `{` بعدَ الاسمِ قد يَكونُ قوسَ معامَلاتٍ مُسمّاةٍ لا الجسم.
String _fnBody(String src, String decl) {
  final i = src.indexOf(decl);
  if (i < 0) throw StateError('لم يُوجَد: $decl');
  var j = i + decl.length;
  var paren = 0;
  for (; j < src.length; j++) {
    if (src[j] == '(') paren++;
    if (src[j] == ')') {
      paren--;
      if (paren == 0) {
        j++;
        break;
      }
    }
    if (paren == 0 && src[j] == '{') break;
  }
  final open = src.indexOf('{', j);
  if (open < 0) throw StateError('لا جسمَ لـ$decl');
  var depth = 0;
  for (var k = open; k < src.length; k++) {
    if (src[k] == '{') depth++;
    if (src[k] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, k + 1);
    }
  }
  throw StateError('جسمٌ غيرُ مُوازَنٍ لـ$decl');
}

void main() {
  group('(أ) القاعدةُ سلوكاً — النائبُ', () {
    test('الغيابُ والفراغُ والمسافاتُ نائبةٌ كلُّها', () {
      expect(nativePayPlaceholder(null), isTrue);
      expect(nativePayPlaceholder(''), isTrue);
      expect(nativePayPlaceholder('   '), isTrue);
    });

    test('بادئةُ REPLACE نائبةٌ أيّاً كانت الحالةُ أو ما بعدَها', () {
      expect(nativePayPlaceholder('REPLACE_WITH_GOOGLE_MERCHANT_ID'), isTrue);
      expect(nativePayPlaceholder('replace_with_service_id'), isTrue);
      expect(nativePayPlaceholder('  REPLACE_ME  '), isTrue);
    });

    test('قيمةٌ حقيقيّةٌ ليست نائبةً — ولا تُطابَقُ بالاحتواء', () {
      expect(nativePayPlaceholder('BCR2DN4T2ABCDEFG'), isFalse);
      // «REPLACE» في وسطِ القيمةِ لا يَجعلُها نائبةً: البادئةُ هي المِقياس.
      expect(nativePayPlaceholder('merchant-REPLACE-suffix'), isFalse);
    });
  });

  group('(ب) القاعدةُ سلوكاً — بطاقةُ Google Pay', () {
    Map<String, Object?> live() => {
          'provider': 'google_pay',
          'data': {
            'environment': 'PRODUCTION',
            'allowedPaymentMethods': [
              {
                'tokenizationSpecification': {
                  'parameters': {'gatewayMerchantId': 'pk_live_realkey'}
                }
              }
            ],
            'merchantInfo': {'merchantId': 'BCR2DN4T2ABCDEFG'},
          },
        };

    test('بطاقةٌ مُهيَّأةٌ بالكاملِ تُقرأُ حيّةً', () {
      expect(googlePayConfigIsLive(live()), isTrue);
    });

    test('environment: TEST يُخفي الزرَّ ولو كان كلُّ ما عداه صحيحاً', () {
      final c = live();
      (c['data'] as Map)['environment'] = 'TEST';
      expect(googlePayConfigIsLive(c), isFalse,
          reason: 'TEST تُعيدُ رمزاً تجريبيّاً من Google — لا مال');
    });

    test('مُعرِّفُ تاجرٍ نائبٌ يُخفي الزرّ', () {
      final c = live();
      ((c['data'] as Map)['merchantInfo'] as Map)['merchantId'] =
          'REPLACE_WITH_GOOGLE_MERCHANT_ID';
      expect(googlePayConfigIsLive(c), isFalse);
    });

    test('مفتاحُ ميسر التجريبيُّ يُخفي الزرّ', () {
      final c = live();
      final m = ((c['data'] as Map)['allowedPaymentMethods'] as List).first;
      ((m as Map)['tokenizationSpecification'] as Map)['parameters'] = {
        'gatewayMerchantId': 'pk_test_f5iq1FWaMMhuGSQwwDEDab293A1MErQocpF87gAQ'
      };
      expect(googlePayConfigIsLive(c), isFalse);
    });

    test(
        'يَفشلُ مُغلَقاً: شكلٌ غيرُ متوقَّعٍ أو حقلٌ غائبٌ يُقرأُ غيرَ مُهيَّأ',
        () {
      expect(googlePayConfigIsLive(null), isFalse);
      expect(googlePayConfigIsLive('نص'), isFalse);
      expect(googlePayConfigIsLive(<String, Object?>{}), isFalse);
      expect(googlePayConfigIsLive({'data': 'نص'}), isFalse);
      expect(
          googlePayConfigIsLive({
            'data': {'environment': 'PRODUCTION'}
          }),
          isFalse);
      expect(
          googlePayConfigIsLive({
            'data': {
              'environment': 'PRODUCTION',
              'merchantInfo': {'merchantId': 'X'},
              'allowedPaymentMethods': <Object?>[],
            }
          }),
          isFalse,
          reason: 'قائمةُ طرائقَ فارغةٌ لا تُقرأُ مُهيَّأة');
    });
  });

  group('(ج) الأصلُ المشحون', () {
    test('مُصرَّحٌ به في pubspec وموجودٌ على القرص', () {
      expect(File(kGooglePayConfigAsset).existsSync(), isTrue,
          reason: '$kGooglePayConfigAsset غيرُ موجود');
      expect(File('pubspec.yaml').readAsStringSync(),
          contains(kGooglePayConfigAsset),
          reason: 'أصلٌ غيرُ مُصرَّحٍ به لا يُحزَمُ، فيَرمي عند القراءة');
    });

    test('يُقرأُ غيرَ مُهيَّأٍ اليومَ — فالزرُّ مخفيّ', () {
      final decoded =
          jsonDecode(File(kGooglePayConfigAsset).readAsStringSync());
      expect(googlePayConfigIsLive(decoded), isFalse,
          reason:
              'إن صارَ هذا الأصلُ حيّاً فقد هُيّئَ Google Pay فعلاً — وحينَها '
              'يُراجَعُ هذا الفحصُ ويُحذَفُ، ولا يُسكَت.');
    });
  });

  group('(د) السطحانِ يُنادِيانِ القاعدةَ', () {
    test('زرُّ Google Pay مشروطٌ بـ_googlePayLive وmoyasarReady', () {
      final code = stripComments(_screen());
      final i = code.indexOf('GooglePayButton(');
      expect(i, greaterThan(0), reason: 'لم يُوجَد زرُّ Google Pay');
      final before = code.substring(0, i);
      final gate = before.lastIndexOf('if (_isNativeAndroid');
      expect(gate, greaterThan(0),
          reason: 'لا شرطَ أندرويد قبلَ زرِّ Google Pay');
      final cond = before.substring(gate, before.indexOf('[', gate) + 1);
      expect(cond, contains('_googlePayLive'),
          reason: 'الزرُّ غيرُ مشروطٍ بأنّ الإعدادَ يَقبضُ مالاً — '
              'وهو العطلُ الذي وُجدَ هذا الملفُّ لأجلِه');
      expect(cond, contains('moyasarReady'),
          reason: 'الرمزُ يُسلَّمُ إلى ميسر، فبلا مفتاحٍ لا معنى للزرّ');
    });

    test('_googlePayLive افتراضُه false ويُضبَطُ من القاعدةِ وحدَها', () {
      final code = stripComments(_screen());
      expect(code, contains('bool _googlePayLive = false'),
          reason: 'fail-closed: الزرُّ مخفيٌّ حتى يَثبُتَ أنّ الإعدادَ حيّ');
      expect(code, contains('googlePayAssetIsLive()'),
          reason: 'لا قراءةَ للأصلِ إلّا عبرَ القاعدة');
      expect(code.contains("jsonDecode"), isFalse,
          reason: 'لا تحليلَ إنلاين لبطاقةِ الإعدادِ في الشاشة');
    });

    test('حارسُ Samsung يَمُرُّ بالقاعدةِ، ولا نسخةَ إنلاين باقيةً', () {
      final code = stripComments(_screen());
      expect(code, contains('nativePayPlaceholder(samsungServiceId)'),
          reason: 'حارسُ Samsung كان صحيحاً — ويَجبُ أن يَصيرَ نداءً للقاعدةِ '
              'كي لا تَنحرِفَ نسختانِ من سؤالٍ واحد');
      expect(code.contains("startsWith('REPLACE')"), isFalse,
          reason: 'نسخةٌ إنلاين من القاعدةِ باقيةٌ في الشاشة');
    });

    test('مسارُ الأصلِ لا يُكتَبُ نصّاً في الشاشة', () {
      final code = stripComments(_screen());
      expect(code.contains("'assets/google_pay_config.json'"), isFalse,
          reason: 'المسارُ في kGooglePayConfigAsset — موضعٌ واحد');
      expect(code, contains('kGooglePayConfigAsset'));
    });
  });

  group('(هـ) شواهدُ التعليل', () {
    test('القاعدةُ لا تَرمي: مُنادِيها يُسقِطُ مستقبَلَها في initState', () {
      final body = _fnBody(
          File('lib/utils/native_pay_config.dart').readAsStringSync(),
          'Future<bool> googlePayAssetIsLive()');
      expect(body, contains('try'));
      expect(body, contains('catch'));
      expect(body, contains('return false'),
          reason: 'تعذُّرُ القراءةِ يُقرأُ «غيرُ مُهيَّأ» — fail-closed');
    });

    test('المسارُ الآخرُ الذي يُسلَّمُ إليه الرمزُ ما زال قائماً', () {
      // لو زالَ هذا فالزرُّ بلا وجهةٍ أصلاً، ويُراجَعُ التعليلُ لا يُسكَت.
      expect(File('lib/services/moyasar_service.dart').readAsStringSync(),
          contains('processGooglePayToken'));
    });
  });
}
