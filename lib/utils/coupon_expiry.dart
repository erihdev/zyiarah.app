/// انتهاءُ الكوبون — الجانبُ الكاتبُ لما تَقرؤه `functions/coupons.js`.
///
/// `showDatePicker` يُعيد **منتصفَ الليل** من اليومِ المختار، و`expiry` يُقارَن
/// `expiry.isBefore(now)` في العميلِ و`exp < nowMs` في الخادم — فكوبونٌ تقول
/// بطاقتُه «ينتهي 2026-12-31» كان ميتاً صبحَ ذلك اليوم، وكوبونُ «ينتهي اليوم»
/// ميتاً منذ لحظةِ إنشائه. آخرُ لحظةٍ من اليومِ تَجعلُ اليومَ المكتوبَ يومَ
/// عملٍ كاملاً كما تَقرؤه الأدمن.
///
/// مرآةُ `endOfLocalDay` في `admin_panel/src/utils/couponExpiry.ts` —
/// و`test/coupon_contract_test.dart` يُثبّت أنّ المحرّرَين لا يَفترقان.
DateTime endOfDayLocal(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
