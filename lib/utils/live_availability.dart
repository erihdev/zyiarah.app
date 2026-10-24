import 'dart:async';

import 'package:flutter/widgets.dart';

/// كم ثانيةً بينَ قراءتَي إتاحةٍ والعميلةُ على شاشةِ الحجز.
///
/// **الأخضرُ وعدٌ لا لقطة** (قرار المالك 2026-10-24): اليومُ والساعةُ
/// يُرسَمانِ أخضرَ لأنّ الخادمَ متأكّدٌ أنّ سائقاً مؤهَّلاً متاحٌ حينَها
/// والسقفَ اليوميَّ يَتّسع، وأحمرَ لغيرِ ذلك — **ويتغيّرانِ وحدَهما** حين
/// يَتغيّرُ الواقع: عميلةٌ أخرى أخذت آخرَ مقعد، أو سائقٌ فُعِّل، أو حجزٌ أُلغي.
/// كانت الإتاحةُ تُقرأُ مرّةً عند فتحِ الشاشة، فيبقى اليومُ أخضرَ بعد امتلائه
/// حتى شاشةِ الدفع، وأحمرَ بعد أن يَتّسع حتى تَخرجَ وتعود.
///
/// والقراءةُ من `getHourlyAvailability` (Admin SDK) لا مستمعُ Firestore:
/// القواعدُ تَمنعُ العميلةَ من قراءةِ طلباتِ غيرِها، وهو ما يُعَدّ.
const Duration kAvailabilityRefresh = Duration(seconds: 30);

/// يُعيدُ قراءةَ الإتاحةِ دوريّاً ما دامت الشاشةُ أمامَ العميلة، وفوراً عند
/// العودةِ إلى التطبيق، ولا شيءَ في الخلفيّة.
///
/// `onRefresh` هو مُحمِّلُ الشاشةِ نفسُه بوضعِه الصامت: لا دوّارَ ولا شاشةَ
/// خطأٍ فوقَ بياناتٍ صالحة، ولا نقلَ للاختيارِ تحتَ إصبعِها — اليومُ الذي
/// امتلأ يَصيرُ أحمرَ ويُقالُ لها ذلك.
class LiveAvailability with WidgetsBindingObserver {
  LiveAvailability(this.onRefresh, {this.interval = kAvailabilityRefresh});

  final Future<void> Function() onRefresh;
  final Duration interval;
  Timer? _timer;
  bool _inFlight = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  /// قراءةٌ واحدةٌ في الطيران: شبكةٌ بطيئةٌ لا تُكدِّسُ نداءاتٍ متراكبة.
  Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await onRefresh();
    } catch (_) {
      // الوضعُ الصامتُ يَبتلعُ أخطاءَه بنفسِه؛ وهذا حارسٌ أخير لا يُسقِطُ المؤقّت.
    } finally {
      _inFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      _schedule();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }
}
