import 'package:flutter/material.dart';

class ZyiarahStrings {
  // التطبيقُ عربيٌّ فقط: لا شيءَ يُغيّر هذه القيمة بعد زوال setLocale الميّتة،
  // فـisArabic ثابتٌ صحيح وكلُّ الفروع الإنجليزيّة أدناه غيرُ قابلةٍ للوصول.
  static const Locale _currentLocale = Locale('ar');

  static bool get isArabic => _currentLocale.languageCode == 'ar';

  // --- Common Strings ---
  static String get save => isArabic ? "حفظ" : "Save";
  static String get cancel => isArabic ? "إلغاء" : "Cancel";

  // --- Dashboard ---
  static String get dashboardTitle => isArabic ? "الرئيسية" : "Home";
  static String get servicesHeader => isArabic ? "خدماتنا" : "Our Services";
  
  // --- Tracking ---
  static String get track => isArabic ? "تتبع" : "Track";
  static String get view => isArabic ? "عرض" : "View";
  static String get driverOnWay => isArabic ? "السائق في الطريق" : "Driver is on the way";
  static String get serviceInProgress => isArabic ? "جاري تنفيذ الخدمة" : "Service in progress";
  static String get orderScheduled => isArabic ? "حجز مجدول" : "Scheduled booking";
  static String get driverAssigned => isArabic ? "تم تعيين السائق" : "Driver assigned";
  static String get orderAccepted => isArabic ? "تم تأكيد الحجز" : "Booking confirmed";
  static String get tapToTrackMap => isArabic ? "اضغطي للمتابعة المباشرة على الخريطة" : "Tap to track live on map";
  static String get tapToViewDetails => isArabic ? "اضغطي لعرض التفاصيل" : "Tap to view details";

  // --- Support ---

  // --- Orders ---
  static String get orderStatus => isArabic ? "حالة الطلب" : "Order Status";

  // --- Admin ---
  static String get adminPanel => isArabic ? "لوحة الإدارة" : "Admin Panel";
  static String get ordersManagement => isArabic ? "إدارة الطلبات" : "Order Management";
  static String get storeManagement => isArabic ? "إدارة المتجر" : "Store Management";
  static String get unifiedStaffManagement => isArabic ? "إدارة منسوبي النظام" : "Unified Staff Management";
  static String get systemSettings => isArabic ? "المزيد" : "More";
  static String get logout => isArabic ? "تسجيل الخروج" : "Logout";

  // --- Feedback & Ratings ---
  static String get lowRatingPrompt => isArabic ? "يؤسفنا سماع ذلك، ما هو السبب الرئيسي؟" : "We are sorry to hear that. What is the reason?";
  static String get selectReasonHint => isArabic ? "اختاري السبب..." : "Select reason...";
  static String get attachEvidence => isArabic ? "إرفاق صورة للمشكلة (اختياري)" : "Attach problem image (optional)";
  static String get evidenceAttached => isArabic ? "تم إرفاق صورة الإثبات" : "Evidence image attached";
  static List<String> get lowRatingReasons => isArabic 
    ? ["عدم تقديم الخدمة المتوقعة", "تأخر الكادر عن الموعد", "سوء في التعامل", "عمل غير مكتمل", "أخرى"]
    : ["Expectations not met", "Staff delayed", "Poor treatment", "Incomplete work", "Other"];
}
