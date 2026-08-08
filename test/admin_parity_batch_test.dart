import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// حارسات دفعة إغلاق فجوات التكافؤ بين واجهتَي الإدارة (2026-08-08).
/// كل اختبار هنا يقابل خللاً **حقيقياً** كُشف بتدقيق 39 وكيلاً، لا مجرد تفضيل شكلي.
void main() {
  String read(String p) => File(p).readAsStringSync();
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      })
      .join('\n');

  final zones = read('lib/screens/admin/admin_hourly_zones_screen.dart');
  final webSettings = read('admin_panel/src/pages/Settings.tsx');
  final webDrivers = read('admin_panel/src/pages/Drivers.tsx');

  test('جدول ساعات المنطقة لا يُعاد كتابته إلا إن لُمس فعلاً', () {
    // **فقدان بيانات:** scheduleData مُهيّأة من المستند، فالشرط القديم
    // (scheduleData != null) كان صادقاً دائماً لأي منطقة لها جدول — فمَن يفتح
    // الحوار ليعدّل سعراً يُعيد كتابة الجدول بلقطة لحظة الفتح، ماسحاً أي
    // فتح/إقفال ساعة غيّره زميل في الأثناء.
    expect(zones.contains('bool scheduleTouched = false'), isTrue);
    expect(zones.contains('scheduleTouched = true'), isTrue);
    expect(zones.contains('if (scheduleTouched && scheduleData != null)'), isTrue);
  });

  test('سجل التدقيق الخادمي بمخطط الشاشة لا مخطط مخالف', () {
    // الشاشة تُرتّب على timestamp — وFirestore يستبعد ما لا يحمل حقل الترتيب —
    // وتُطابق الأسماء بأحرف كبيرة. كانت الدالة تكتب created_at واسماً صغيراً،
    // فلم تظهر أي عملية حذف خادمية في السجل إطلاقاً.
    final fn = read('functions/index.js');
    expect(fn.contains('action: "DELETE_DRIVER"'), isTrue);
    expect(fn.contains('timestamp: admin.firestore.FieldValue.serverTimestamp()'),
        isTrue);
    expect(read('lib/services/audit_service.dart').contains("'timestamp'"), isTrue,
        reason: 'مصدر المخطط الذي نطابقه');
  });

  test('لوحة الويب تكتب سجل تدقيق لعملياتها', () {
    expect(File('admin_panel/src/services/audit.ts').existsSync(), isTrue);
    final audit = read('admin_panel/src/services/audit.ts');
    expect(audit.contains('timestamp: serverTimestamp()'), isTrue);
    for (final a in ['REGISTER_DRIVER', 'UPDATE_DRIVER', 'TOGGLE_DRIVER_STATUS']) {
      expect(webDrivers.contains('AUDIT.$a'), isTrue, reason: '$a غير مسجَّل');
    }
    for (final a in ['CREATE_ZONE', 'UPDATE_ZONE', 'DELETE_ZONE',
      'TOGGLE_SERVICE_STATUS', 'APPLY_PRICES_TO_ZONES']) {
      expect(webSettings.contains('AUDIT.$a'), isTrue, reason: '$a غير مسجَّل');
    }
  });

  test('حقل المركبة يُكتب بالاسمين فلا يُظلّل أحدهما الآخر', () {
    // الويب يقرأ `vehicle || car_info`، فأول تعديل من الويب يُنشئ vehicle ثم
    // يبقى كل تعديل لاحق من التطبيق (يكتب car_info) غير مرئي هناك للأبد.
    expect(webDrivers.contains('car_info: editForm.vehicle'), isTrue);
    expect(read('lib/screens/admin/admin_drivers_screen.dart')
        .contains("'vehicle': carInfoCtrl.text.trim()"), isTrue);
  });

  test('تصنيف الكادر وحقول الهوية موجودة في الويب', () {
    // كان الويب يثبّت 'driver' فيدخل كادر التنظيف عدّاد السائقين وكشف الرواتب.
    expect(webDrivers.contains('كادر تنظيف'), isTrue);
    expect(webDrivers.contains('role: staffType'), isTrue);
    expect(webDrivers.contains('type: staffType'), isTrue);
    for (final f in ['nationality', 'id_number', 'id_expiry', 'license_info']) {
      expect(webDrivers.contains(f), isTrue, reason: '$f مفقود في الويب');
    }
  });

  test('نصف القطر محدود في الواجهتين', () {
    // 0 كم يمنع كل الحجوزات، و500 كم يبتلع المحافظات المجاورة في مطابقة المنطقة.
    expect(zones.contains('radiusVal < 1 || radiusVal > 100'), isTrue);
    expect(webSettings.contains('radius < 1 || radius > 100'), isTrue);
  });

  test('الإحداثيات اليدوية في الويب محروسة بحدود جازان', () {
    // النقر على الخريطة كان محروساً والحقلان اليدويان لا.
    expect(webSettings.contains('!isInJazan(lat, lng)'), isTrue);
  });

  test('السعة اليومية ترفض الصفر والسالب في التطبيق', () {
    // حدٌّ صفر يُغلق الحجز في كل المناطق بلا رسالة خطأ.
    expect(read('lib/screens/admin/admin_settings_screen.dart')
        .contains('capacity == null || capacity < 1'), isTrue);
  });

  test('نسخ الأسعار لا يعرض المحافظة على نفسها', () {
    expect(webSettings.contains('zones.filter(z => z.id !== editingZoneId)'), isTrue);
  });

  test('أزرار المحافظة ظاهرة على اللمس', () {
    // Tailwind v4 يترجم hover داخل @media (hover: hover) — فعلى جهاز لمسي تبقى
    // الأزرار بشفافية 0 للأبد (غير مرئية، وليست معطّلة).
    expect(webSettings.contains('[@media(hover:hover)]:opacity-0'), isTrue);
    // النمط القديم بالضبط: شفافية صفر غير مشروطة ثم إظهار بالتحويم وحده.
    expect(webSettings.contains('gap-1 opacity-0 group-hover:opacity-100'), isFalse,
        reason: 'النمط القديم المعتمد على hover وحده');
  });

  test('نشر الأسعار دفعةً موجود في الويب ولا يمسّ غير الأسعار', () {
    expect(webSettings.contains('handleApplyPricesToZones'), isTrue);
    expect(webSettings.contains('writeBatch(db)'), isTrue);
    // لا يكتب اسماً/موقعاً/نصف قطر/تفعيلاً/جدولاً — يمسح خصوصية كل محافظة.
    final fn = webSettings.substring(
        webSettings.indexOf('handleApplyPricesToZones'),
        webSettings.indexOf('const handleSaveCapacity'));
    for (final forbidden in ['name:', 'centerLoc', 'radiusKm', 'enabled:', 'schedule']) {
      expect(fn.contains(forbidden), isFalse,
          reason: '$forbidden يجب ألا يُنشر على المحافظات الأخرى');
    }
  });

  test('محرّر جدول الساعات موجود في الويب بنفس مخطط التطبيق', () {
    final web = read('admin_panel/src/utils/zoneSchedule.ts');
    final editor = read('admin_panel/src/components/ZoneScheduleEditor.tsx');
    // نفس المفاتيح حرفياً — الخادم (getHourlyAvailability) يقرؤها كما هي.
    for (final k in ['enabled', 'weekly', 'blackouts', 'windows', 'closed']) {
      expect(web.contains(k), isTrue, reason: '$k مفقود في مخطط الويب');
    }
    // الساعات تُخزَّن 24 وتُعرَض 12 — تخزين نصّي يكسر حساب الإتاحة بصمت.
    expect(web.contains('formatHour12'), isTrue);
    // قصّ الساعات المقفلة على النطاق — نفس قاعدة _emit في التطبيق.
    expect(web.contains('h >= v.start && h < v.end'), isTrue);
    expect(read('lib/screens/admin/admin_zone_schedule_editor.dart')
        .contains('h >= e.value.start && h < e.value.end'), isTrue,
        reason: 'المصدر الذي نطابقه');
    // فتح/إقفال ساعة بعينها + الفترات الاستثنائية + أيام الإغلاق.
    expect(editor.contains('toggleHour'), isTrue);
    expect(editor.contains('فترات فتح استثنائية'), isTrue);
    expect(editor.contains('أيام إغلاق كامل'), isTrue);
  });

  test('الويب أيضاً لا يكتب الجدول إلا إن لُمس', () {
    // نفس فقدان البيانات الذي أُصلح في التطبيق — لا نكرّره في الويب.
    expect(webSettings.contains('scheduleDraft ? { schedule: scheduleDraft } : {}'),
        isTrue);
    expect(webSettings.contains('setScheduleDraft(null)'), isTrue,
        reason: 'فتح محافظة للتعديل يبدأ بمسوّدة فارغة');
  });

  test('مدير العمليات يصل نطاق التغطية ولا يرى ما ترفضه القواعد', () {
    // firestore.rules: service_zones = isOrdersManager، system_configs = super_admin.
    expect(read('admin_panel/src/config/access.ts')
        .contains("'/settings':         ['super_admin', 'admin', 'orders_manager']"),
        isTrue);
    expect(webSettings.contains("const zonesOnly = role === 'orders_manager'"), isTrue);
    expect(webSettings.contains("allTabs.filter(t => t.id === 'coverage')"), isTrue);
  });
}
