import 'package:flutter/material.dart';

class ZyiarahStrings {
  static Locale _currentLocale = const Locale('ar');

  static void setLocale(Locale locale) {
    _currentLocale = locale;
  }

  static bool get isArabic => _currentLocale.languageCode == 'ar';

  // --- Common Strings ---
  static String get appName => "Zyiarah MaidJoy Edition";
  static String get hello => isArabic ? "أهلاً بك" : "Welcome";
  static String get loading => isArabic ? "جاري التحميل..." : "Loading...";
  static String get save => isArabic ? "حفظ" : "Save";
  static String get cancel => isArabic ? "إلغاء" : "Cancel";

  // --- Dashboard ---
  static String get dashboardTitle => isArabic ? "الرئيسية" : "Home";
  static String get maintenanceAlertTitle => isArabic ? "مهم: عرض سعر الصيانة جاهز" : "Important: Maintenance Price Quote Ready";
  static String get maintenanceAlertBody => isArabic ? "لديك طلب بانتظار الدفع، اضغط للمتابعة." : "You have a request waiting payment, tap to proceed.";
  static String get servicesHeader => isArabic ? "خدماتنا" : "Our Services";
  static String get latestBookings => isArabic ? "آخر الحجوزات" : "Latest Bookings";
  static String get noBookings => isArabic ? "لا توجد حجوزات" : "No Bookings";
  static String get portalSubtitle => isArabic ? "بوابتك لخدمات منزلية متكاملة" : "Your portal to home services";
  static String get waitingPayment => isArabic ? "بانتظار الدفع" : "Waiting Payment";
  static String get viewAndPayNow => isArabic ? "استعرض وادفع الآن" : "View & Pay Now";
  
  // --- Tracking ---
  static String get track => isArabic ? "تتبع" : "Track";
  static String get driverOnWay => isArabic ? "السائق في الطريق" : "Driver is on the way";
  static String get serviceInProgress => isArabic ? "جاري تنفيذ الخدمة" : "Service in progress";
  static String get tapToTrackMap => isArabic ? "اضغط للمتابعة المباشرة على الخريطة" : "Tap to track live on map";

  // --- Support ---
  static String get supportTitle => isArabic ? "الدعم الفني" : "Support";
  static String get sendReply => isArabic ? "إرسال الرد" : "Send Reply";

  // --- Orders ---
  static String get myOrders => isArabic ? "طلباتي" : "My Orders";
  static String get orderStatus => isArabic ? "حالة الطلب" : "Order Status";

  // --- Admin ---
  static String get adminPanel => isArabic ? "لوحة الإدارة" : "Admin Panel";
  static String get ordersManagement => isArabic ? "إدارة الطلبات" : "Order Management";
  static String get supportTickets => isArabic ? "تذاكر الدعم" : "Support Tickets";
  static String get storeManagement => isArabic ? "إدارة المتجر" : "Store Management";
  static String get driversStaff => isArabic ? "الكوادر والسائقين" : "Staff & Drivers";
  static String get unifiedStaffManagement => isArabic ? "إدارة منسوبي النظام" : "Unified Staff Management";
  static String get analyticsReports => isArabic ? "التحليلات والتقارير" : "Analytics & Reports";
  static String get systemSettings => isArabic ? "إعدادات النظام" : "System Settings";
  static String get accessDenied => isArabic ? "عذراً.. غير مصرح لك" : "Sorry.. Access Denied";
  static String get contactAdmin => isArabic ? "لا تملك صلاحيات كافية للوصول للوحة التحكم. يرجى التواصل مع المسؤول." : "You do not have sufficient permissions. Contact admin.";
  static String get logout => isArabic ? "تسجيل الخروج" : "Logout";

  // --- Feedback & Ratings ---
  static String get lowRatingPrompt => isArabic ? "يؤسفنا سماع ذلك، ما هو السبب الرئيسي؟" : "We are sorry to hear that. What is the reason?";
  static String get selectReasonHint => isArabic ? "اختر السبب..." : "Select reason...";
  static String get attachEvidence => isArabic ? "إرفاق صورة للمشكلة (اختياري)" : "Attach problem image (optional)";
  static String get evidenceAttached => isArabic ? "تم إرفاق صورة الإثبات" : "Evidence image attached";
  static List<String> get lowRatingReasons => isArabic 
    ? ["عدم تقديم الخدمة المتوقعة", "تأخر الكادر عن الموعد", "سوء في التعامل", "عمل غير مكتمل", "أخرى"]
    : ["Expectations not met", "Staff delayed", "Poor treatment", "Incomplete work", "Other"];
}
