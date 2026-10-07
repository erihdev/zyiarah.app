import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:zyiarah/main.dart';
import 'package:zyiarah/utils/user_facing_error.dart';

class GlobalErrorHandler {

  /// يُسجّلُ الخطأَ ويُظهِرُ لها **سببَه** إن كان معروفاً.
  ///
  /// كان يُطابِقُ ثلاثَ كلماتٍ في `toString()` ويَطرحُ ما كتبَه الخادمُ، فسببٌ
  /// مثل «الرصيد غير كافٍ» يَصِلُها «حدث خطأ غير متوقع. يُرجى المحاولة مرة
  /// أخرى» — ونصيحةُ الإعادةِ هناك خاطئةٌ لا ناقصة. القرارُ الآن في
  /// `userFacingError` مرّةً واحدةً لكلِّ الأسطح (`lib/utils/user_facing_error.dart`).
  static void handleError(dynamic error, [StackTrace? stackTrace]) {
    // Send silently to Crashlytics to keep app stable
    FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);

    _showToast(userFacingError(error), isError: true);
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
