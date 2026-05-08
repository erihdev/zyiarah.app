import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:zyiarah/main.dart';

class GlobalErrorHandler {

  /// Logs the error and displays a unified user-friendly snackbar.
  static void handleError(dynamic error, [StackTrace? stackTrace]) {
    String message = "حدث خطأ غير متوقع. جرب مرة أخرى.";
    
    // Customize user message based on standard exceptions
    if (error.toString().contains("network") || error.toString().contains("offline")) {
      message = "لا يوجد اتصال بالإنترنت. يرجى التحقق من الشبكة.";
    } else if (error.toString().contains("unavailable")) {
      message = "تعذّر الاتصال بالخادم. يرجى المحاولة مرة أخرى.";
    } else if (error.toString().contains("permission-denied")) {
      message = "ليس لديك الصلاحية لإتمام هذه العملية.";
    }

    // Send silently to Crashlytics to keep app stable
    FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);

    _showToast(message, isError: true);
  }

  /// Displays success messages gracefully.
  static void showSuccess(String message) {
    _showToast(message, isError: false);
  }

  static void _showToast(String message, {bool isError = false}) {
    messengerKey.currentState?.removeCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(15),
      ),
    );
  }
}
