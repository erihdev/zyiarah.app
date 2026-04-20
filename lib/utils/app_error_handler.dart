import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:zyiarah/main.dart'; // To access messengerKey

/// نظام معالجة الأخطاء الشامل في تطبيق زيارة
/// يمنع "صمت التطبيق" عند فشل العمليات الحساسة
class ZyiarahErrorHandler {
  
  /// عرض رسالة خطأ للمستخدم وتسجيلها تقنياً
  static void handleError(dynamic error, {StackTrace? stack, String? customMessage}) {
    final String message = customMessage ?? _parseError(error);
    
    // 1. تسجيل الخطأ في Crashlytics لغرض المتابعة البرمجية
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);

    // 2. إخطار المستخدم عبر الـ Global Messenger
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  /// تبسيط رسائل الخطأ التقنية لتكون مفهومة للعميل
  static String _parseError(dynamic error) {
    if (error is String) return error;
    
    final String errStr = error.toString().toLowerCase();
    if (errStr.contains('network') || errStr.contains('connection')) {
      return "مشكلة في الاتصال بالإنترنت، يرجى المحاولة لاحقاً.";
    }
    if (errStr.contains('permission-denied')) {
      return "عذراً، لا تملك الصلاحية للقيام بهذا الإجراء.";
    }
    if (errStr.contains('user-not-found')) {
      return "عذراً، الحساب غير موجود.";
    }
    
    return "حدث خطأ غير متوقع. جاري العمل على إصلاحه.";
  }
}

/// غلاف لنتائج العمليات (Result Wrapper)
class ServiceResult<T> {
  final T? data;
  final String? error;
  final bool success;

  ServiceResult.success(this.data) : error = null, success = true;
  ServiceResult.failure(this.error) : data = null, success = false;
}
