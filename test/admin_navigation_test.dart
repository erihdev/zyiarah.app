// حرّاسُ تبسيطِ تنقّلِ الإدارة (2026-10-11) ومحرّرِ المناطق.
//
// كلُّ فحصٍ يَشدُّ قدرةً لا اسماً: التبويبُ يُبنى عند أوّلِ زيارة، والشاشاتُ
// المدموجةُ تَبقى بأدوارِها السابقة، واسمُ المنطقةِ — مفتاحُ ربطِ الطلبات —
// لا يُرمَّزُ ولا يَنقلُ المركزَ عند إعادةِ التسمية.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String p) => File(p)
    .readAsStringSync()
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');

void main() {
  group('لوحةُ الإدارة: تبويباتٌ كسولة', () {
    final dash = _code('lib/screens/admin/admin_dashboard_screen.dart');

    test('التبويبُ بانٍ لا ودجةٌ مبنيّة، ولا يُبنى قبلَ زيارتِه', () {
      expect(dash.contains("'page':"), isFalse,
          reason: 'ودجاتٌ مبنيّةٌ سلفاً = كلُّ التبويباتِ تَفتحُ استعلاماتِها عند الدخول');
      expect(dash.contains("'build': () =>"), isTrue);
      expect(dash.contains('_visitedTabs.contains(i)'), isTrue);
      expect(dash.contains('_visitedTabs.add(index)'), isTrue,
          reason: 'بلا تسجيلِ الزيارةِ لا يُبنى التبويبُ أبداً');
      expect(dash.contains('IndexedStack('), isTrue,
          reason: 'التبويبُ المُزارُ يَحفظُ حالتَه');
    });

    test('المتجرُ يَحملُ طلباتِ المتجرِ بأدوارِها السابقة', () {
      final hub = _code('lib/screens/admin/admin_store_hub_screen.dart');
      expect(hub.contains("static const productRoles = ['super_admin', 'accountant_admin', 'marketing_admin'];"), isTrue);
      expect(hub.contains("static const orderRoles = ['super_admin', 'orders_manager'];"), isTrue);
      expect(dash.contains('AdminStoreHubScreen.tabRoles'), isTrue);
      final more = _code('lib/screens/admin/admin_more_screen.dart');
      expect(more.contains('AdminStoreOrdersScreen()'), isFalse,
          reason: 'بلاطةٌ ثانيةٌ للشاشةِ نفسِها');
    });

    test('الباقاتُ شاشةٌ واحدةٌ تُضمِّنُ المحرِّرَين بلا شريطٍ مزدوج', () {
      final pk = _code('lib/screens/admin/admin_packages_screen.dart');
      expect(pk.contains('AdminSubscriptionsScreen(embedded: true)'), isTrue);
      expect(pk.contains('AdminEventWorkerPackagesScreen(embedded: true)'), isTrue);
      for (final f in [
        'lib/screens/admin/admin_subscriptions_screen.dart',
        'lib/screens/admin/admin_event_worker_packages_screen.dart',
      ]) {
        expect(_code(f).contains('appBar: widget.embedded ? null : AppBar('), isTrue,
            reason: '$f يَرسمُ شريطَه داخلَ الحاوية');
      }
    });

    test('المتجرُ يُضمِّنُ شاشتَيه بلا شريطٍ مزدوج، وتَحتفظانِ بشريطِهما وحدَهما', () {
      // كان تبويبُ المتجرِ يَرسمُ شريطَ اللوحةِ ثمّ شريطَ «إدارة المتجر» تحتَه
      // (وشريطَ «مبيعات المتجر» في الشريحةِ الثانية) — الشكلُ الذي أُصلحَ في
      // الطلباتِ والباقاتِ بعلَمِ `embedded`، وتُرِكَ هنا.
      final hub = _code('lib/screens/admin/admin_store_hub_screen.dart');
      expect(RegExp(r'AdminStoreScreen\(role: role, embedded: true\)').allMatches(hub).length, 2,
          reason: 'الشريحةُ المفردةُ والتبويبُ كلاهما مُضمَّن');
      expect(RegExp(r'AdminStoreOrdersScreen\(embedded: true\)').allMatches(hub).length, 2);
      for (final f in [
        'lib/screens/admin/admin_store_screen.dart',
        'lib/screens/admin/admin_store_orders_screen.dart',
      ]) {
        final c = _code(f);
        expect(c.contains('this.embedded = false'), isTrue, reason: '$f: الافتراضُ شريطٌ خاصّ');
        expect(c.contains('appBar: widget.embedded ? null : AppBar('), isTrue,
            reason: '$f يَرسمُ شريطَه داخلَ الحاوية');
      }
      // من الإحصاءاتِ تُفتَحُ طلباتُ المتجرِ وحدَها فتَحتاجُ شريطَها.
      final ins = _code('lib/screens/admin/admin_insights_screen.dart');
      expect(ins.contains('const AdminStoreOrdersScreen()'), isTrue);
    });

    test('التحليلاتُ تُفتَحُ من الإحصاءاتِ بأدوارِ بلاطتِها السابقة', () {
      final ins = _code('lib/screens/admin/admin_insights_screen.dart');
      expect(ins.contains('const AdminAnalyticsScreen()'), isTrue);
      expect(ins.contains("const ['admin', 'super_admin', 'accountant_admin', 'orders_manager']"), isTrue);
      expect(ins.contains('if (_canOpenAnalytics)'), isTrue);
    });

    test('تصديرُ CSV عبرَ المُهرِّبِ المشترك لا بناءٌ يدويّ', () {
      final more = _code('lib/screens/admin/admin_more_screen.dart');
      expect(more.contains('ZyiarahExportUtil.convertToCsv('), isTrue);
      expect(RegExp(r"buffer\.writeln\('\$\{d\[").hasMatch(more), isFalse,
          reason: 'فواصلُ عاريةٌ: حقنُ صيغةٍ وصفوفٌ مكسورة');
    });
  });

  group('محرّرُ المناطق: الاسمُ مفتاحٌ لا تسمية', () {
    final z = _code('lib/screens/admin/admin_hourly_zones_screen.dart');

    test('تعديلُ منطقةٍ قائمةٍ لا يُرمِّزُ الاسمَ ولا ينقلُ المركز', () {
      final i = z.indexOf('nameDebounce?.cancel();');
      expect(i, greaterThan(-1));
      final guard = z.indexOf('if (doc != null) {', i);
      final geocode = z.indexOf('_geocodeZoneName(q)', i);
      expect(guard, greaterThan(i));
      expect(geocode, greaterThan(guard),
          reason: 'حارسُ المنطقةِ القائمةِ يَجبُ أن يَسبقَ الترميز');
      final branch = z.substring(guard, geocode);
      expect(branch.contains('return;'), isTrue,
          reason: 'الحارسُ يَخرجُ قبلَ الترميز');
      expect(z.contains('if (!ctx.mounted || locationPinned) return;'), isTrue,
          reason: 'موقعٌ وضعَه الأدمنُ بيدِه لا يَطمسُه ترميزٌ متأخّر');
    });

    test('إعادةُ التسميةِ تُنبَّهُ عنها وتُؤكَّدُ قبلَ الحفظ', () {
      expect(z.contains('if (renamed())'), isTrue);
      final confirm = z.indexOf('تأكيد تغيير اسم المنطقة');
      final saving = z.indexOf('setDialogState(() => isSaving = true);', confirm);
      expect(confirm, greaterThan(-1));
      expect(saving, greaterThan(confirm),
          reason: 'التأكيدُ قبلَ الكتابةِ لا بعدَها');
      expect(z.contains("'renamed_from': originalName"), isTrue,
          reason: 'سجلُّ التدقيقِ يَحفظُ الاسمَ القديم');
    });

    test('الخريطةُ الكاملةُ تفتحُ على المركزِ الحاليِّ وتُعيدُ نصفَ القطر', () {
      expect(z.contains('initialLocation: selectedGeo'), isTrue);
      expect(z.contains('adjustableRadius: true'), isTrue);
      final p = _code('lib/screens/location_picker_screen.dart');
      expect(p.contains("Navigator.pop(context, {'location': geoPoint, 'radiusKm': _radiusKm});"), isTrue);
      // موقعٌ معروفٌ لا يُستبدَلُ بموقعِ الجهاز.
      final init = p.indexOf('void initState()');
      final body = p.substring(init, p.indexOf('Future<void> _locateMe', init));
      expect(body.contains('if (init != null)'), isTrue);
      expect(body.indexOf('_locateMe('), greaterThan(body.indexOf('} else {')));
    });

    test('المُنزلِقُ يَكتبُ في حقلِ نصفِ القطرِ نفسِه — تحقّقُ الحفظِ باقٍ', () {
      expect(z.contains('radiusCtrl.text = r % 1 == 0'), isTrue);
      expect(z.contains('radiusVal == null || radiusVal < 1 || radiusVal > 100'), isTrue);
    });
  });
}
