import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس ترقية Tabby إلى 2.x (2026-09-29).
///
/// العطل الذي يمنعه: منذ 2.0.0 صار `TabbySDK().setup()` نداءً شبكياً يُنتظَر،
/// **ويفشل فشلاً صريحاً** بلا إعادة محاولة ولا احتياطي (ServerException عند
/// غير 200، FormatException عند ردٍّ مشوَّه، وأخطاء النقل تمرّ كما هي).
/// وهو يُستدعى في `main` **قبل `runApp`**؛ فاستثناء غير ملتقَط يعني أن انقطاع
/// شبكة عابراً لحظة الفتح يمنع إقلاع التطبيق كلّه — لا تابي وحدها.
String _read(String p) => File(p).readAsStringSync();

void main() {
  test('الإصدار 2.x وقد اختفت مكتبة العرض التي كانت تُعطب iOS 26', () {
    expect(_read('pubspec.yaml').contains('tabby_flutter_inapp_sdk: ^2.'), isTrue);
    // 2.0.0 أسقطت flutter_inappwebview (سبب EXC_BAD_ACCESS على iOS 26)
    // واستبدلتها بـ webview_flutter الذي نعتمده أصلاً مباشرةً.
    expect(_read('pubspec.lock').contains('flutter_inappwebview'), isFalse,
        reason: 'عودتها تعني عودة انهيار iOS 26');
    expect(_read('pubspec.yaml').contains('webview_flutter:'), isTrue);
  });

  test('setup يُنتظَر، وبمهلة، وداخل try — الفشل يخفي تابي لا يمنع الإقلاع', () {
    final s = _read('lib/services/tabby_service.dart');
    final i = s.indexOf('static Future<void> initialize()');
    expect(i, greaterThan(-1), reason: 'initialize اختفت — حدِّث الحارس');
    final body = s.substring(i, s.indexOf('\n  }', i));

    expect(body.contains('await TabbySDK().setup('), isTrue,
        reason: '2.x تُعيد Future؛ نداءٌ بلا await يترك SDK غير جاهز بصمت');
    expect(body.contains('.timeout('), isTrue,
        reason: 'بلا مهلة يعلّق إقلاع التطبيق على استجابة طرف ثالث');
    expect(body.contains('} catch (e) {'), isTrue,
        reason: 'استثناء غير ملتقَط قبل runApp = تطبيق لا يُقلع');
    // وعند الفشل تبقى تابي مخفيّة لا «جاهزة» كذباً.
    final catchBlock = body.substring(body.indexOf('} catch (e) {'));
    expect(catchBlock.contains('_initialized = false'), isTrue);

    // main ما زالت تنتظرها (لا نريد نداءً معلّقاً بلا التقاط).
    expect(_read('lib/main.dart').contains('await TabbyService.initialize()'), isTrue);
  });

  test('شاشة الدفع تعيد المحاولة كي لا يُخفي انقطاعٌ عابر تابي طوال الجلسة', () {
    final s = _read('lib/services/tabby_service.dart');
    expect(s.contains('static Future<bool> ensureInitialized()'), isTrue);
    final pay = _read('lib/screens/payment_summary_screen.dart');
    expect(pay.contains('TabbyService.ensureInitialized()'), isTrue);
    // الخيار ما زال محكوماً بالجاهزية الحقيقية.
    expect(pay.contains('TabbyService.isAvailable'), isTrue);
  });
}
