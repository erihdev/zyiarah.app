// يثبت أن نمط الحماية المستخدم في generateAndUploadInvoice يحوّل أي عملية شبكية
// معلّقة (اتصال ضعيف/محجوب) إلى فشل محدود المدة بدل تجمّد إلى الأبد.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// نموذج مصغّر لنفس منطق الخدمة: عملية شبكية بمهلة، ثم علامة فشل عند التجاوز.
Future<String?> uploadWithTimeout(Future<void> Function() networkOp,
    {required void Function() markFailed}) async {
  try {
    await networkOp().timeout(const Duration(milliseconds: 200));
    return 'download-url';
  } catch (_) {
    markFailed();
    return null;
  }
}

void main() {
  test('العملية المعلّقة للأبد تعود خلال المهلة بقيمة null وتعلّم الفشل', () async {
    var failed = false;
    final sw = Stopwatch()..start();

    // عملية لا تكتمل أبداً (تحاكي رفع Storage على اتصال محجوب).
    final result = await uploadWithTimeout(
      () => Completer<void>().future, // لا يكتمل مطلقاً
      markFailed: () => failed = true,
    );
    sw.stop();

    expect(result, isNull, reason: 'يجب أن تفشل بأمان لا أن تعلّق');
    expect(failed, isTrue, reason: 'يجب أن تُعلّم الوثيقة بالفشل لعرض زر الإعادة');
    expect(sw.elapsedMilliseconds, lessThan(2000),
        reason: 'يجب أن تعود خلال المهلة، لا أن تدور للأبد');
  });

  test('العملية الناجحة تعيد الرابط دون تعليم فشل', () async {
    var failed = false;
    final result = await uploadWithTimeout(
      () async {}, // تكتمل فوراً
      markFailed: () => failed = true,
    );
    expect(result, 'download-url');
    expect(failed, isFalse);
  });
}
