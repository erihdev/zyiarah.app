// مرآةُ `lib/utils/driver_activation.dart` — الحقولُ الثلاثةُ تُكتَبُ معاً.
//
// الخادمُ يَقرأُ `is_active` وحدَه للأهليّة، وهذه اللوحةُ تَبني شارةَ الحالةِ
// ومفتاحَ الإيقافِ على `is_suspended`، و`is_available` حالةُ اتّصالِ السائق.
// فتعطيلٌ يَكتبُ حقلاً واحداً يُظهرُ السائقَ هنا على غيرِ حقيقتِه — وقد حدثَ
// ذلك فعلاً من مفتاحِ شاشةِ السائقين في تطبيقِ الإدارة.
//
// والتفعيلُ لا يَكتبُ `is_available`: الاتّصالُ قرارُ السائق.

export type DriverActivation =
  | { is_active: true; is_suspended: false }
  | { is_active: false; is_suspended: true; is_available: false };

export function driverActivationFields(active: boolean): DriverActivation {
  return active
    ? { is_active: true, is_suspended: false }
    : { is_active: false, is_suspended: true, is_available: false };
}

/** هل يُعَدُّ معطَّلاً؟ أيُّ الحقلَين يَكفي — نفسُ قراءةِ الخادم. */
export function driverIsDisabled(
  d: { is_active?: boolean; is_suspended?: boolean },
): boolean {
  return d.is_active === false || d.is_suspended === true;
}
