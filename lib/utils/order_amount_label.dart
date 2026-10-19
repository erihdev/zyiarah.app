import 'package:zyiarah/utils/home_packages.dart' show formatSarAny;

/// النصُّ المعروضُ للعميلة مكانَ مبلغِ الطلب.
///
/// زيارةُ الباقةِ تُولَّدُ خادميّاً بـ`amount: 0` و`payment_method:
/// 'subscription'` (`_generateContractVisits`) — فقيمتُها دُفعت مع العقد لا مع
/// الزيارة. وعرضُ «0.00 ر.س» عليها يُقرأُ خدمةً مجّانيّةً أو خطأً في الفاتورة،
/// فتُقال «ضمن الباقة» بدلاً من رقمٍ لا يَصدُق.
String clientOrderAmountLabel(Map<String, dynamic> order) {
  if (order['payment_method'] == 'subscription') return 'ضمن الباقة';
  return '${formatSarAny(order['amount'])} ر.س';
}
