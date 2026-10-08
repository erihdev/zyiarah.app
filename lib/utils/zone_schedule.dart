/// جدولُ فتحِ المنطقةِ كما يُعيدُه `getHourlyAvailability` — قاعدةٌ واحدةٌ
/// لخمسةِ أسطحٍ كانت تَقرؤه خمسَ قراءاتٍ مختلفة.
///
/// **والخادمُ يُعيدُ الجدولَ مفتاحُه `zoneName`**: بلا الاسمِ تَصيرُ
/// `zoneSchedule` هي `null` فيُقرأُ كلُّ يومٍ مفتوحاً بالنطاقِ الافتراضيِّ
/// (`zoneDayScheduleForDate(null, …)` تُعيدُ `{range: DEFAULT_OPEN, closed: []}`)،
/// و`zoneMaxOrdersPerDay` و`zoneDailyCounts` و`closedHours` تَعودُ خاليةً.
/// فالاسمُ شرطٌ لا تحسين، ومَن يُحدّدُ منطقتَه بعدَ أوّلِ جلبٍ يَلزمُه جلبٌ ثانٍ.
///
/// وثلاثةُ أسطحٍ كانت تَقرأُ الجدولَ كاملاً (`hourly_details_screen`،
/// و`booking_slot_picker`، وبوّابةُ `payment_summary_screen`)، **وشاشتا العقدِ
/// تَقرآنِ `closedHours` وحدَها**: تَحصُرانِ ساعاتِ البدءِ بـ8..22 مكتوبةً بيدٍ
/// لا بنطاقِ فتحِ المنطقة، ولا تَقرآنِ `closedDates` إطلاقاً. وهما المسارُ
/// الذي **لا يَمُرُّ ببوّابةِ الدفع** (التوقيعُ يَلي الاختيارَ مباشرةً) ولا
/// يُعيدُ الخادمُ فحصَه (`zoneDayScheduleForDate` قارئُها الوحيدُ هذه الدالّةُ
/// نفسُها)، فشاشةُ العقدِ هي الحارسُ الوحيدُ لزياراتٍ تُجدوَلُ لأسابيع.
///
/// و`defaultOpen` كان يُعيدُه الخادمُ **ولا يَقرؤه أحد**، والنطاقُ الافتراضيُّ
/// مكتوبٌ بيدٍ في خمسةِ مواضع — شكلُ قصّةِ الضريبةِ بعينِه: تغييرُ
/// `DEFAULT_OPEN` خادميّاً يَترُكُ خمسَ نسخٍ تَقولُ 8..22.
library;

/// آخرُ ملجأٍ حين يَفشلُ النداءُ فلا يَصِلُ `defaultOpen` أصلاً — **الموضعُ
/// الوحيدُ** الذي يَكتبُ النطاقَ حرفيّاً، ويُقابِلُه الحارسُ بـ`DEFAULT_OPEN`
/// في `functions/index.js`.
const List<int> kFallbackOpenHours = [8, 22];

/// عدٌّ يَتجاوزُ أيَّ سعةٍ حقيقيّة: الساعةُ التي أقفلَها المالكُ تُحقَنُ به
/// فتُقرأُ «ممتلئة» في كلِّ قارئٍ بلا فرعٍ خاصٍّ بها.
const int kClosedHourSlotSentinel = 999999;

/// ما يَلزمُ لرسمِ مواعيدِ منطقةٍ: نطاقُ فتحِ كلِّ يوم، والأيّامُ المغلقةُ
/// كلّيّاً، والساعاتُ المقفلةُ داخلَ النطاق.
class ZoneSchedule {
  /// `yyyy-MM-dd` → `[فتح، إغلاق]` كما أعادَها الخادمُ لهذه المنطقة.
  final Map<String, List<int>> openHours;

  /// أيّامٌ لا تُخدَمُ فيها المنطقةُ أصلاً (إغلاقٌ صريحٌ أو يومٌ خارجَ الجدول).
  final Set<String> closedDates;

  /// `yyyy-MM-dd` → ساعاتٌ أقفلَها المالكُ داخلَ نطاقِ الفتح.
  final Map<String, List<int>> closedHours;

  /// النطاقُ الافتراضيُّ **كما يَقولُه الخادمُ** لا كما يُكتَبُ في الشاشة.
  final List<int> defaultOpen;

  const ZoneSchedule({
    this.openHours = const {},
    this.closedDates = const {},
    this.closedHours = const {},
    this.defaultOpen = kFallbackOpenHours,
  });

  /// قراءةُ حِمْلِ `getHourlyAvailability` — متسامحةٌ مع الغيابِ وبأنواعٍ
  /// مفحوصة: ردٌّ ناقصٌ يُقرأُ «بلا جدول» لا يَرمي في منتصفِ الرسم.
  factory ZoneSchedule.fromAvailability(Map? data) {
    final d = data ?? const {};
    return ZoneSchedule(
      openHours: _hourMap(d['openHours']),
      // `as List?` على قيمةٍ غيرِ قائمةٍ **يَرمي** — وحِمْلٌ ناقصٌ يَجب أن
      // يُقرأ «بلا جدول» لا أن يَرمي في منتصفِ رسمِ الشريط.
      closedDates: _dateSet(d['closedDates']),
      closedHours: _hourMap(d['closedHours']),
      defaultOpen: _range(d['defaultOpen']) ?? kFallbackOpenHours,
    );
  }

  /// نطاقُ فتحِ اليومِ، وإلّا الافتراضيُّ الذي أعادَه الخادم.
  List<int> openHoursFor(String dateKey) => openHours[dateKey] ?? defaultOpen;

  /// المنطقةُ لا تُخدَمُ في هذا اليومِ أصلاً — **سببٌ غيرُ الامتلاء**.
  bool dateIsClosed(String dateKey) => closedDates.contains(dateKey);

  /// ساعاتُ البدءِ التي تَتّسعُ لمهمّةٍ بطولِ [durationHours] **داخلَ نطاقِ
  /// الفتح** — فارغةٌ إن أُغلِقَ اليومُ أو لم تَتّسعِ المدّةُ للنطاق.
  ///
  /// ولا قَصَّ إلى النطاقِ الافتراضيّ: محرِّرُ الجدولِ يُجيزُ بدايةً من الصفرِ
  /// ونهايةً حتى 23 (`hour_range.dart`)، وبوّابةُ الدفعِ تَقرأُ `openHours`
  /// خامّاً — فقَصُّ العرضِ إلى 8..22 يَحجبُ ساعةً تَقبلُها البوّابةُ نفسُها.
  List<int> startHoursFor(String dateKey, int durationHours) {
    if (dateIsClosed(dateKey)) return const [];
    if (durationHours <= 0) return const [];
    final open = openHoursFor(dateKey);
    final first = open[0];
    final last = open[1] - durationHours;
    if (last < first) return const [];
    return List.generate(last - first + 1, (i) => first + i);
  }

  /// الساعاتُ المقفلةُ تُحقَنُ في عدّادِ الخانات ممتلئةً — فيَستبعدُها كلُّ
  /// قارئٍ للعدّادِ بلا أن يَعرِفَ بالجدولِ شيئاً.
  void markClosedHoursFull(Map<String, int> slotCounts) {
    closedHours.forEach((date, hours) {
      for (final h in hours) {
        slotCounts['${date}_${h.toString().padLeft(2, '0')}:00'] =
            kClosedHourSlotSentinel;
      }
    });
  }

  static Set<String> _dateSet(Object? raw) =>
      raw is List ? raw.map((e) => e.toString()).toSet() : const {};

  static Map<String, List<int>> _hourMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<int>>{};
    raw.forEach((k, v) {
      if (v is List) {
        final hours = v
            .map((e) => e is num ? e.toInt() : int.tryParse('$e'))
            .whereType<int>()
            .toList();
        if (hours.isNotEmpty) out[k.toString()] = hours;
      }
    });
    return out;
  }

  static List<int>? _range(Object? raw) {
    final r = _hourMap({'x': raw})['x'];
    return (r != null && r.length >= 2) ? [r[0], r[1]] : null;
  }
}
