import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/popup_gate.dart';

/// **الإعلانُ المنبثقُ كان يَتخطّى إيقافَ التسويقِ كلَّه.**
///
/// القاعدةُ المعلنةُ في `functions/notify_prefs.js`: البثُّ الإداريُّ
/// (`notifications_log`) **تسويقيٌّ افتراضياً** ما لم يُوسَم
/// `operational: true`، و`_deliverBroadcast` يُسقط عن التسويقيِّ كلَّ من أوقف
/// «العروض والتسويق» — بوشاً وصندوقاً داخل التطبيق.
///
/// والمنبثقُ لا يَمرُّ بذلك المسارِ إطلاقاً، من طرفَيه:
///
///   * `onNotificationCreated` يَرجعُ مبكراً عند `type === "popup"` —
///     **بحقّ**: المنبثقُ نافذةٌ داخلَ التطبيقِ فقط، وبلا ذلك الحارسِ كان
///     إعلانٌ واحدٌ يُطلق ثلاثَ قنواتٍ دفعةً واحدة. لكنّ الأثرَ الجانبيَّ أنّ
///     `excludeOptedOut` لا يَعملُ معه.
///   * والعميلُ يَقرأ `notifications_log where type == 'popup'` **مباشرةً**
///     (`firestore.rules` تُجيزه لكلِّ مسجَّل) — فلا إسقاطَ خادميّاً أصلاً.
///
/// فمن أوقفت التسويقَ **صراحةً** كانت تَرى الإعلانَ على كلِّ فتحٍ للتطبيقِ
/// طولَ أربعٍ وعشرين ساعة. القرارُ الآن نقيٌّ في `lib/utils/popup_gate.dart`
/// ويُسأل عميليّاً، لأنّ القراءةَ عميليّة.
///
/// **ولم يُغيَّر** أنّه لا علمَ «شُوهد» في أيِّ مكان: الإعلانُ يُعاد على كلِّ
/// فتحٍ داخلَ النافذة. سلوكٌ قائمٌ وقرارُه للمالك، لا عطلٌ أُصلح بالسكوت.
void main() {
  final repo = Directory.current.path;
  String read(String rel) => File('$repo/$rel').readAsStringSync();
  String stripLineComments(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  final now = DateTime.utc(2026, 10, 5, 12);
  Map<String, dynamic> popup({DateTime? sentAt, bool? operational}) => {
        'title': 'عرض',
        'body': 'نصّ',
        if (sentAt != null) 'sent_at': Timestamp.fromDate(sentAt),
        if (operational != null) 'operational': operational,
      };

  group('القاعدة', () {
    test('تسويقيٌّ حديثٌ: يُعرض للمُفعِّلةِ ولا يُعرض للمُوقِفة — العطلُ بعينه',
        () {
      final fresh = popup(sentAt: now.subtract(const Duration(hours: 2)));
      expect(shouldShowPopup(fresh, now: now, marketingEnabled: true), isTrue);
      expect(shouldShowPopup(fresh, now: now, marketingEnabled: false), isFalse,
          reason: 'من أوقفت التسويقَ صراحةً كانت تَراه على كلِّ فتح');
    });

    test('التشغيليُّ يَصلُ الجميعَ — كما في البثِّ تماماً', () {
      final op = popup(
          sentAt: now.subtract(const Duration(hours: 2)), operational: true);
      expect(shouldShowPopup(op, now: now, marketingEnabled: false), isTrue);
      expect(shouldShowPopup(op, now: now, marketingEnabled: true), isTrue);
      // و«غيرُ تشغيليّ» تُقرأ صارمةً: أيُّ قيمةٍ غيرِ `true` تسويقيّة.
      for (final v in [false, 'true', 1, null]) {
        final x = popup(sentAt: now.subtract(const Duration(hours: 2)));
        if (v != null) x['operational'] = v;
        expect(shouldShowPopup(x, now: now, marketingEnabled: false), isFalse,
            reason: 'operational=$v');
      }
    });

    test('النافذةُ أربعٌ وعشرون ساعة — والحدُّ مُغلَق', () {
      expect(kPopupMaxAge, const Duration(hours: 24));
      final almost = popup(
          sentAt: now.subtract(kPopupMaxAge - const Duration(seconds: 1)));
      expect(shouldShowPopup(almost, now: now, marketingEnabled: true), isTrue);
      final exact = popup(sentAt: now.subtract(kPopupMaxAge));
      expect(shouldShowPopup(exact, now: now, marketingEnabled: true), isFalse);
      final old = popup(sentAt: now.subtract(const Duration(days: 30)));
      expect(shouldShowPopup(old, now: now, marketingEnabled: true), isFalse);
    });

    test('بلا لحظةِ إرسالٍ لا نَعرض — عمرٌ مجهولٌ قد يكون من العامِ الماضي', () {
      expect(shouldShowPopup(popup(), now: now, marketingEnabled: true),
          isFalse);
      expect(
          shouldShowPopup({'sent_at': 'ليس طابعاً', 'title': 'x'},
              now: now, marketingEnabled: true),
          isFalse);
      expect(shouldShowPopup(null, now: now, marketingEnabled: true), isFalse);
    });

    test('لحظةُ إرسالٍ في المستقبلِ لا تُعرض (ساعةُ جهازٍ متأخّرة)', () {
      final future = popup(sentAt: now.add(const Duration(hours: 3)));
      expect(shouldShowPopup(future, now: now, marketingEnabled: true), isFalse);
    });
  });

  group('قراءةُ التفضيل', () {
    test('الغيابُ = مُفعَّل — نفسُ تسامحِ شاشةِ التفضيلات', () {
      expect(marketingEnabledFrom(null), isTrue);
      expect(marketingEnabledFrom({}), isTrue);
      expect(marketingEnabledFrom({'notification_prefs': {}}), isTrue);
      expect(marketingEnabledFrom({'notification_prefs': 'نصّ'}), isTrue);
    });

    test('و`false` صريحةٌ وحدَها تُوقِف', () {
      expect(
          marketingEnabledFrom({
            'notification_prefs': {'marketing': false}
          }),
          isFalse);
      expect(
          marketingEnabledFrom({
            'notification_prefs': {'marketing': true}
          }),
          isTrue);
    });

    test('والقاعدةُ هي عينُها في شاشةِ التفضيلات — لا نسخةٌ ثانية', () {
      final screen =
          stripLineComments(read('lib/screens/client_notifications_screen.dart'));
      expect(screen, contains("prefs['marketing'] != false"),
          reason: 'القاعدةُ تغيّرت هناك — وهذه نسختُها');
    });
  });

  group('حارسُ المصدر', () {
    final svc = stripLineComments(read('lib/services/popup_service.dart'));

    test('الخدمةُ تَسألُ القرارَ ولا تُعيدُ صياغتَه', () {
      expect(svc, contains('shouldShowPopup(data'),
          reason: 'الخدمةُ لا تَسألُ البوّابة');
      expect(svc, contains('marketingEnabledFrom('));
      expect(svc.contains('.inHours < 24'), isFalse,
          reason: 'شرطُ العمرِ عاد إنلاين — فالبوّابةُ بلا موضوع');
    });

    test('وتَقرأُ التفضيلَ فقط عند وجودِ إعلانٍ غيرِ تشغيليّ', () {
      final i = svc.indexOf('Future<bool> marketingEnabled()');
      expect(i, greaterThan(0), reason: 'القراءةُ المؤجَّلةُ اختفت');
      final body = svc.substring(i, svc.indexOf('\n      }', i));
      expect(body, contains("data['operational'] == true"),
          reason: 'التشغيليُّ يجب أن يَخرجَ قبل أيِّ قراءة');
      expect(body, contains('kNetCallTimeout'),
          reason: 'قراءةٌ بلا مهلةٍ تُعلّق المسارَ بصمت');
    });

    test('وغيابُ الهويّةِ لا يَعرضُ تسويقاً', () {
      expect(svc, contains('if (uid == null) return false;'),
          reason: 'بلا هويّةٍ لا نَعرفُ التفضيلَ — والخطأُ يجب أن يَميلَ '
              'إلى احترامِه لا إلى العرض');
    });

    test('والخادمُ ما زال يَستثني المنبثقَ من قنواتِ البثّ', () {
      // لو زالَ ذلك الاستثناءُ لعاد الإعلانُ يُطلق ثلاثَ قنوات، **و**لصار
      // الإسقاطُ الخادميُّ يَعملُ فيُغني عن هذه البوّابة — فالحالتان تستحقّان
      // مراجعةً لا مروراً صامتاً.
      final idx = stripLineComments(read('functions/index.js'));
      expect(idx, contains('if (newValue.type === "popup") return;'));
    });
  });
}
