/// هل سطحُ الدفعِ الأصليِّ مُهيَّأٌ فعلاً للمالِ الحقيقيّ؟
///
/// القاعدةُ كانت مُنفَّذةً في سطحٍ واحدٍ من اثنَين — وهو النمطُ المسجَّلُ في
/// `CLAUDE.md` مراراً. حارسُ Samsung Pay في `payment_summary_screen` كان
/// `samsungServiceId.isEmpty || samsungServiceId.startsWith('REPLACE')` ثمّ
/// `SizedBox.shrink()`، وهو **الصواب**: مُعرِّفُ خدمةٍ نائبٌ يَعني زرّاً لا
/// يَقبضُ شيئاً، فيُخفى. وزرُّ Google Pay على بُعدِ تسعينَ سطراً فوقَه كان
/// مشروطاً بـ`_isNativeAndroid && _googlePayConfigFuture != null` وحدَه —
/// و`_googlePayConfigFuture` **لا يَكونُ `null` على أندرويد أبداً** (يُسنَدُ في
/// `initState` من أصلٍ مُصرَّحٍ به في `pubspec.yaml`)، فالشرطُ صحيحٌ دائماً
/// والزرُّ يُرسَمُ لكلِّ مستخدمةٍ مسجَّلةٍ على أندرويد.
///
/// وما تَحملُه بطاقةُ الإعدادِ المشحونةُ يَجعلُ ذلك عطلاً لا تجميلاً:
/// `"environment": "TEST"` و`gatewayMerchantId` مفتاحُ ميسر **التجريبيُّ**
/// (`pk_test_…`) و`"merchantId": "REPLACE_WITH_GOOGLE_MERCHANT_ID"` — أي أنّ
/// المُعرِّفَ يَبدأُ بـ`REPLACE` حرفيّاً، وهو عينُ ما يَفحصُه حارسُ Samsung.
/// فالضغطةُ تُعيدُ رمزاً تجريبيّاً من Google ثمّ تُرسَلُ إلى ميسر بمفتاحٍ
/// تجريبيّ: إمّا شحنةٌ تجريبيّةٌ أو فشلٌ — ولا مالَ حقيقيٌّ في الحالتَين.
///
/// فالقاعدةُ تَسكنُ هنا مرّةً، ويُنادِيها السطحانِ معاً.
/// `test/native_pay_config_test.dart` يَشدُّ ذلك.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// الأصلُ المُصرَّحُ به في `pubspec.yaml`. موضعٌ واحدٌ لا نصٌّ مكتوبٌ مرّتَين.
const String kGooglePayConfigAsset = 'assets/google_pay_config.json';

/// بادئةُ النائبِ التي يَضَعُها قالبُ الإعداد.
const String kNativePayPlaceholderPrefix = 'REPLACE';

/// قيمةٌ نائبةٌ أو غائبة: زرٌّ عليها لا يَقبضُ شيئاً، فيُخفى.
///
/// الغيابُ والفراغُ والمسافاتُ كلُّها نائبة، والمقارنةُ غيرُ حسّاسةٍ للحالةِ
/// كي لا يَنجوَ `replace_with_…` من الحارس.
bool nativePayPlaceholder(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return true;
  return v.toUpperCase().startsWith(kNativePayPlaceholderPrefix);
}

/// هل بطاقةُ إعدادِ Google Pay تَقبضُ مالاً حقيقيّاً؟
///
/// ثلاثةُ شروطٍ، وكلٌّ منها يَكفي وحدَه لإخفاءِ الزرّ:
///  * `environment` غيرُ `PRODUCTION` — `TEST` تُعيدُ رمزاً تجريبيّاً من
///    Google، فالزرُّ لا يَقبضُ ولو كان كلُّ ما عداه صحيحاً.
///  * `merchantInfo.merchantId` نائبٌ — وهو حالُ الأصلِ المشحونِ اليوم.
///  * `gatewayMerchantId` مفتاحُ ميسر التجريبيُّ (`pk_test_`) — شحنةٌ
///    تجريبيّةٌ لا مال.
///
/// ويَفشلُ **مُغلَقاً**: شكلٌ غيرُ متوقَّعٍ أو حقلٌ غائبٌ يُقرأُ «غيرُ مُهيَّأ»،
/// لأنّ إظهارَ زرِّ دفعٍ على إعدادٍ لا نَفهمُه أسوأُ من إخفائه.
bool googlePayConfigIsLive(Object? decoded) {
  if (decoded is! Map) return false;
  final data = decoded['data'];
  if (data is! Map) return false;

  final env = (data['environment'] ?? '').toString().trim().toUpperCase();
  if (env != 'PRODUCTION') return false;

  final merchant = data['merchantInfo'];
  if (merchant is! Map) return false;
  if (nativePayPlaceholder(merchant['merchantId']?.toString())) return false;

  final methods = data['allowedPaymentMethods'];
  if (methods is! List || methods.isEmpty) return false;
  for (final m in methods) {
    if (m is! Map) return false;
    final spec = m['tokenizationSpecification'];
    if (spec is! Map) return false;
    final params = spec['parameters'];
    if (params is! Map) return false;
    final gw = (params['gatewayMerchantId'] ?? '').toString().trim();
    if (nativePayPlaceholder(gw)) return false;
    if (gw.toLowerCase().startsWith('pk_test_')) return false;
  }
  return true;
}

/// يَقرأُ الأصلَ ويُقرّرُ. **لا يَرمي بحال** — فمُنادِيه يُسقِطُ مستقبَلَه في
/// `initState` ولا مَن يَلتقطُ رميَه (قاعدةُ «ما لا يُنتظَرُ لا يَرمي»).
Future<bool> googlePayAssetIsLive() async {
  try {
    final raw = await rootBundle.loadString(kGooglePayConfigAsset);
    return googlePayConfigIsLive(jsonDecode(raw));
  } catch (e, st) {
    debugPrint('googlePayAssetIsLive: $e\n$st');
    return false;
  }
}
