// الأخضرُ وعدٌ لا لقطة (قرار المالك 2026-10-24) — `lib/utils/live_availability.dart`.
//
// اليومُ والساعةُ أخضرانِ لأنّ الخادمَ متأكّدٌ أنّ سائقاً مؤهَّلاً متاحٌ
// والسقفَ يَتّسع، وأحمرانِ لغيرِ ذلك، ويتغيّرانِ وحدَهما حين يتغيّرُ الواقع.
// كانت الإتاحةُ تُقرأُ مرّةً عند فتحِ الشاشة.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/live_availability.dart';

void main() {
  group('سلوكاً', () {
    testWidgets('يُعيدُ القراءةَ كلَّ دورة، ويَتوقّفُ في الخلفيّة، ويُحدِّثُ عند العودة',
        (tester) async {
      var calls = 0;
      final live = LiveAvailability(() async => calls++,
          interval: const Duration(seconds: 30));
      live.start();

      await tester.pump(const Duration(seconds: 29));
      expect(calls, 0, reason: 'لا قراءةَ قبلَ الدورة');
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 3));
      expect(calls, 2, reason: 'قراءاتٌ والتطبيقُ في الخلفيّة');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 3, reason: 'العودةُ لا تُحدِّثُ فوراً — الأخضرُ قديم');
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 4, reason: 'الدورةُ لم تَعُد بعدَ الاستئناف');

      live.dispose();
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 4, reason: 'قراءاتٌ بعدَ إغلاقِ الشاشة');
    });

    testWidgets('قراءةٌ واحدةٌ في الطيران — شبكةٌ بطيئةٌ لا تُكدِّس', (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      final live = LiveAvailability(() {
        calls++;
        return gate.future;
      }, interval: const Duration(seconds: 30));
      live.start();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1, reason: 'نداءاتٌ متراكبةٌ والأوّلُ لم يَعُد');
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
      live.dispose();
    });

    testWidgets('خطأُ القراءةِ لا يُسقِطُ الدورة', (tester) async {
      var calls = 0;
      final live = LiveAvailability(() async {
        calls++;
        throw StateError('network');
      }, interval: const Duration(seconds: 30));
      live.start();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
      live.dispose();
    });
  });

  group('مصدراً: أسطحُ الحجزِ الأربعةُ حيّة', () {
    const surfaces = {
      'lib/screens/hourly_details_screen.dart': '_loadAvailabilityFromServer',
      'lib/screens/event_worker_packages_screen.dart':
          '_loadAvailabilityFromServer',
      'lib/screens/subscription_plans_screen.dart':
          '_loadAvailabilityFromServer',
      'lib/widgets/booking_slot_picker.dart': '_load',
    };

    test('كلُّ سطحٍ يُشغِّلُ التحديثَ الحيَّ ويُطفئُه', () {
      for (final e in surfaces.entries) {
        final src = File(e.key).readAsStringSync();
        expect(src.contains('LiveAvailability(() => ${e.value}(silent: true))'),
            isTrue, reason: '${e.key}: لا تحديثَ حيّ');
        expect(src.contains('_liveAvailability.start()'), isTrue,
            reason: '${e.key}: لا يَبدأ');
        expect(src.contains('_liveAvailability.dispose()'), isTrue,
            reason: '${e.key}: مؤقّتٌ يَعيشُ بعدَ الشاشة');
      }
    });

    test('الوضعُ الصامتُ لا يُحرِّكُ الاختيارَ ولا يَرسمُ خطأً فوقَ بياناتٍ صالحة', () {
      for (final e in surfaces.entries) {
        final src = File(e.key).readAsStringSync();
        expect(src.contains('${e.value}({bool silent = false})'), isTrue,
            reason: '${e.key}: المُحمِّلُ بلا وضعٍ صامت');
        expect(RegExp(r'if \(!silent && _(dateUnavailable|isDayUnavailable)\(')
                .hasMatch(src),
            isTrue,
            reason: '${e.key}: التحديثُ الحيُّ يَنقلُ اليومَ تحتَ إصبعِها');
        expect(src.contains('if (silent) return; // آخرُ قراءةٍ صالحةٍ تبقى'),
            isTrue,
            reason: '${e.key}: فشلٌ عابرٌ يَمحو الأخضرَ والأحمرَ الصالحَين');
        expect(src.contains('اكتمل'), isTrue,
            reason: '${e.key}: اختيارٌ امتلأ تحتَ إصبعِها ولا يُقالُ لها');
      }
    });

    test('الإتاحةُ من الخادم — لا مستمعَ على طلباتِ غيرِها', () {
      final rule = File('lib/utils/live_availability.dart').readAsStringSync();
      expect(rule.contains('snapshots('), isFalse,
          reason: 'القواعدُ تَمنعُ قراءةَ طلباتِ غيرِها — المستمعُ يَفشلُ صامتاً');
      expect(kAvailabilityRefresh, const Duration(seconds: 30));
    });
  });
}
