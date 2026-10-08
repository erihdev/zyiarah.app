import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/referral_rewards.dart';

import 'helpers/strip_comments.dart';

/// **وعدُ الإحالةِ كان ستّةَ أرقامٍ مكتوبةٍ بيدٍ عبرَ لغتَين.**
///
/// المكافأةُ تُودَعُ خادميّاً وتُعرَضُ في التطبيقِ وتُرسَلُ في رسالةٍ تَبعثُها
/// العميلةُ **إلى أناسٍ آخرين**، فموضعٌ منسيٌّ يَجعلُ التطبيقَ يَعِدُ برقمٍ
/// لا يَدفعُه — شكلُ قصّةِ الضريبةِ على وعدٍ لا على فاتورة. والستّةُ متّفقةٌ
/// اليومَ، فالتوحيدُ **وقائيٌّ** ويُقالُ كذلك.
void main() {
  final String rewards = File('functions/rewards.js').readAsStringSync();
  final String profile =
      File('lib/screens/profile_screen.dart').readAsStringSync();

  int serverConst(String name) {
    final m = RegExp('const $name = ([0-9]+);').firstMatch(rewards);
    expect(m, isNotNull, reason: 'ثابتُ الخادمِ `$name` زال أو تغيّرَ شكلُه');
    return int.parse(m!.group(1)!);
  }

  group('أرقامُ الإحالة', () {
    test('(أ) الرقمانِ واحدٌ بين اللغتَين', () {
      expect(kReferralRewardSar, serverConst('REFERRAL_REWARD_SAR'),
          reason: 'مكافأةُ المُحيلِ المعروضةُ تُخالفُ ما يُودِعُه الخادم');
      expect(kRefereeDiscountPercent, serverConst('REFEREE_DISCOUNT_PERCENT'),
          reason: 'نسبةُ خصمِ المُحالةِ المعروضةُ تُخالفُ قيمةَ كوبونِها');
    });

    test('(ب) كلُّ موضعٍ خادميٍّ يَقرأُ الثابتَ لا رقماً مكتوباً', () {
      final code = stripComments(rewards);
      // الإيداعُ في المحفظةِ وصفُّ السجلّ.
      expect(code.contains('FieldValue.increment(REFERRAL_REWARD_SAR)'), isTrue,
          reason: 'الإيداعُ لم يَعُدْ من الثابت');
      expect(code.contains('amount: REFERRAL_REWARD_SAR'), isTrue,
          reason: 'صفُّ السجلِّ لم يَعُدْ من الثابت');
      // قيمةُ الكوبونِ ولاحقةُ رمزِه ووصفُه.
      expect(code.contains('value: REFEREE_DISCOUNT_PERCENT'), isTrue,
          reason: 'قيمةُ كوبونِ المُحالةِ مكتوبةٌ بيد');
      expect(
          RegExp(r'REF\$\{refereeUid[^`]*\}\$\{REFEREE_DISCOUNT_PERCENT\}')
              .hasMatch(code),
          isTrue,
          reason: 'لاحقةُ رمزِ الكوبونِ مكتوبةٌ بيدٍ — رمزٌ يَقولُ نسبةً '
              'وقيمةٌ تُخالفُه');
      expect(code.contains(r'خصم الإحالة ${REFEREE_DISCOUNT_PERCENT}%'), isTrue,
          reason: 'وصفُ الكوبونِ يَحملُ نسبةً مكتوبةً بيد');
      // ولا رقمٌ عارٍ باقٍ في جسمِ الصرف.
      final int i = code.indexOf('async function payReferralBonus');
      expect(i, greaterThan(-1), reason: 'دالّةُ الصرفِ زالت');
      final int j = code.indexOf('\nasync function', i + 10);
      final String body = code.substring(i, j < 0 ? code.length : j);
      expect(RegExp(r'[^\w.]50[^\w.]').hasMatch(body), isFalse,
          reason: 'عادَ رقمُ المكافأةِ مكتوباً بيدٍ في جسمِ الصرف');
    });

    test('(ج) ونصّا العميلةِ يُستقرِئانِ الثابتَين لا رقماً', () {
      final code = stripComments(profile);
      // ومبلغُ البطاقةِ يَمُرُّ بـ`formatSar` كقاعدةِ «كلُّ رقمٍ قبلَ ر.س
      // مُنسَّق» — وحارسُها عضَّ على أوّلِ صياغةٍ استقرأت الثابتَ خامّاً،
      // بحقٍّ: لو صارَ `double` يوماً لَطُبعَ «50.0».
      expect(
          code.contains(
              r'${formatSar(kReferralRewardSar.toDouble())} ر.س'),
          isTrue,
          reason: 'بطاقةُ «حسابي» لا تَقرأُ ثابتَ المكافأةِ مُنسَّقاً');
      expect(
          RegExp(r'خصم \$kRefereeDiscountPercent%').allMatches(code).length, 2,
          reason: 'النصّانِ (البطاقةُ ورسالةُ المشاركة) لا يَقرآنِ ثابتَ النسبة');
      // والأرقامُ العاريةُ زالت من النصَّين، مع مضادّةٍ على الخامّ: الشرحُ
      // يَقتبسُ الصيغةَ القديمةَ، فلولا الحجبُ لسقطَ الفحصُ على توثيقِه.
      expect(code.contains('واحصل على 50 ر.س'), isFalse);
      expect(code.contains('خصم 10%'), isFalse);
      expect(profile.contains('خصم 10%'), isTrue,
          reason: 'شرحُ التغييرِ اختفى — فالتجريدُ أعلاه بلا ما يُميّزُه');
    });

    test('(د) شاهدا التعليل: الكوبونُ مخطَّطُ التطبيقِ، والمُحيلُ يُبلَّغ', () {
      final code = stripComments(rewards);
      // قيمةُ الكوبونِ تُقرأُ من `type/value` (مخطَّطُ `validateCoupon`)،
      // فلو تغيّرَ المخطَّطُ لم تَعُدْ النسبةُ هي ما يُطبَّقُ على الطلب.
      expect(code.contains('type: "percentage"'), isTrue,
          reason: 'نوعُ كوبونِ الإحالةِ تغيّرَ — فالنسبةُ لم تَعُدْ نسبة');
      // والمُحيلُ يُبلَّغُ بالمبلغِ نفسِه (دفعةٌ بالرقمِ المُودَع).
      expect(code.contains(r'${REFERRAL_REWARD_SAR.toFixed(2)} ر.س'), isTrue,
          reason: 'دفعةُ المُحيلِ لا تَقرأُ الثابتَ — فتُعلِنُ رقماً آخر');
    });
  });
}
