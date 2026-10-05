import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/order_activity.dart';

/// يُجرّد التعليقاتَ سطراً كاملاً ثمّ يَلتقطُ النصوصَ داخل مجموعةٍ مُسمّاة.
Set<String> _dartSet(String src, String name) {
  final body = src.split('\n').where((l) {
    final t = l.trimLeft();
    return !t.startsWith('//') && !t.startsWith('///');
  }).join('\n');
  final i = body.indexOf('$name = {');
  expect(i, greaterThan(-1), reason: 'لم تُوجد المجموعة $name');
  final j = body.indexOf('};', i);
  final block = body.substring(i, j);
  return RegExp("'([a-z_]+)'")
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

Set<String> _tsSet(String src, String name) {
  final body = src.split('\n').where((l) {
    final t = l.trimLeft();
    return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
  }).join('\n');
  final i = body.indexOf('$name: readonly string[] = [');
  expect(i, greaterThan(-1), reason: 'لم تُوجد المجموعة $name في المرآة');
  final j = body.indexOf('];', i);
  final block = body.substring(i, j);
  return RegExp("'([a-z_]+)'")
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final dartSrc = File('lib/utils/order_activity.dart').readAsStringSync();
  final tsSrc =
      File('admin_panel/src/utils/orderActivity.ts').readAsStringSync();
  final insights =
      File('lib/screens/admin/admin_insights_screen.dart').readAsStringSync();
  final ordersList =
      File('lib/screens/orders_list_screen.dart').readAsStringSync();
  final dashboard =
      File('admin_panel/src/pages/Dashboard.tsx').readAsStringSync();
  final storeService =
      File('lib/services/store_service.dart').readAsStringSync();

  group('القاعدة نفسها', () {
    test('الحالات المنتهية وحدها تُقرأ منتهية', () {
      for (final s in ['delivered', 'completed', 'cancelled', 'rejected']) {
        expect(orderIsOpen(s), isFalse, reason: s);
      }
    });

    test('كل حالة من دورة الحياة الحقيقية تُقرأ مفتوحة', () {
      // المجموعتان من `order_lifecycle.dart` + دورة المتجر + ما قبل الدفع.
      const live = [
        'pending',
        'awaiting_payment',
        'under_review',
        'assigned',
        'scheduled',
        'accepted',
        'on_the_way',
        'in_progress',
        'delivering',
        'processing',
        'shipped',
        'paid',
        'approved',
        'waiting_payment',
      ];
      for (final s in live) {
        expect(orderIsOpen(s), isTrue, reason: s);
      }
    });

    test('حالة لم تُولد بعد تُقرأ مفتوحة — وهذا هو الشق المُصلَح', () {
      // عينُ الخلل: التعدادُ أسقطَ بصمتٍ كلَّ حالةٍ أُضيفت بعده.
      for (final s in ['out_for_delivery', 'preparing', 'redelivery', 'زائدة']) {
        expect(orderIsOpen(s), isTrue, reason: s);
      }
    });

    test('الغائب والفارغ مفتوحان لا منتهيان', () {
      expect(orderIsOpen(null), isTrue);
      expect(orderIsOpen(''), isTrue);
      expect(orderIsOpen('  '), isTrue);
      expect(orderIsOpen(7), isTrue);
    });

    test('المسافات المحيطة لا تُغيّر الحكم', () {
      expect(orderIsOpen(' delivered '), isFalse);
      expect(orderIsOpen(' on_the_way '), isTrue);
    });

    test('«يَنتظرُ إجراءً» هو ما تَعرضُ له الإدارةُ زرّاً', () {
      for (final s in ['under_review', 'delivering', 'processing', 'shipped']) {
        expect(storeOrderNeedsAction(s), isTrue, reason: s);
      }
      // المدفوعُ غيرُ بعد، والمنتهي، وغيرُ الموجود — لا إجراء.
      for (final s in ['awaiting_payment', 'delivered', 'pending', '', 'x']) {
        expect(storeOrderNeedsAction(s), isFalse, reason: s);
      }
      expect(storeOrderNeedsAction(null), isFalse);
    });

    test('«المنتهي» و«يَنتظرُ إجراءً» لا يتقاطعان', () {
      expect(
          kTerminalOrderStatuses.intersection(kStoreNeedsActionStatuses), isEmpty);
    });

    test('refunded ليست حالةَ status — إدراجُها كان سيُعيد الخلل نفسه', () {
      expect(kTerminalOrderStatuses.contains('refunded'), isFalse);
      // والسببُ مكتوبٌ في الملف كي لا تُضاف لاحقاً «تكميلاً».
      expect(dartSrc.contains('payment_status'), isTrue);
    });
  });

  group('المرآة لا تَنفكّ', () {
    test('المجموعتان متطابقتان في الملفَّين', () {
      expect(_tsSet(tsSrc, 'TERMINAL_ORDER_STATUSES'),
          equals(_dartSet(dartSrc, 'kTerminalOrderStatuses')));
      expect(_tsSet(tsSrc, 'STORE_NEEDS_ACTION_STATUSES'),
          equals(_dartSet(dartSrc, 'kStoreNeedsActionStatuses')));
    });

    test('المجموعةُ الدارتيّةُ هي ما يَقرؤه الاختبارُ فعلاً', () {
      // كي لا يَمرَّ تطابقُ نصَّين بينما الكودُ يَستخدمُ مجموعةً ثالثة.
      expect(_dartSet(dartSrc, 'kTerminalOrderStatuses'),
          equals(kTerminalOrderStatuses));
      expect(_dartSet(dartSrc, 'kStoreNeedsActionStatuses'),
          equals(kStoreNeedsActionStatuses));
    });
  });

  group('مواضع الاستدعاء — قاعدةٌ لا تُستدعى قاعدةٌ ميتة', () {
    test('عدّاد «طلبات نشطة» يَمرّ بالقاعدة ثلاثَ مرّات', () {
      expect(RegExp(r'orderIsOpen\(').allMatches(insights).length, 3,
          reason: 'orders + maintenance_requests + store_orders');
      expect(insights.contains("import 'package:zyiarah/utils/order_activity.dart'"),
          isTrue);
    });

    test('لا تعدادَ متبقٍّ في عدّاد اللوحة', () {
      // أيٌّ من هذه الثلاثِ كان يُنتج العدَّ الناقص.
      expect(insights.contains("status == 'assigned'"), isFalse);
      expect(insights.contains("sStatus == 'processing'"), isFalse);
      expect(insights.contains("status == 'waiting_payment'"), isFalse);
    });

    test('تبويبا العميلة بالقاعدة، ولا قائمتَي حالاتٍ بعدها', () {
      expect(RegExp(r'orderIsOpen\(').allMatches(ordersList).length, 4,
          reason: 'شرطان في كلِّ تبويب');
      // الكودُ يَشرحُ القرارَ بتسميةِ القائمةِ المحذوفة، فنُجرّدُ التعليقَ قبل
      // البحث — وإلّا سَقطَ الحارسُ على توثيقِه (وقد سَقطَ).
      final code = ordersList.split('\n').where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      }).join('\n');
      expect(code.contains('activeStatuses'), isFalse);
      expect(code.contains('historyStatuses'), isFalse);
      // وبالمقابل: اللفظُ ما زال في النصِّ الخامّ، فلا يُفرّغُ التجريدُ الحارس.
      expect(ordersList.contains('historyStatuses'), isTrue);
    });

    test('بطاقةُ اللوحةِ تَستعلمُ المجموعةَ لا pending', () {
      expect(dashboard.contains("where('status', '==', 'pending')"), isFalse,
          reason: 'الشرطُ الصفريُّ الأبدي');
      expect(dashboard.contains('STORE_NEEDS_ACTION_STATUSES'), isTrue);
      expect(dashboard.contains("from '../utils/orderActivity'"), isTrue);
    });

    test('عنوانُ البطاقةِ لا يُسمّي خطوةَ موافقةٍ أُلغيت', () {
      expect(dashboard.contains('طلبات بانتظار الموافقة'), isFalse);
      expect(dashboard.contains('طلبات متجر تحتاج إجراء'), isTrue);
    });
  });

  group('الأساس الذي بُنيت عليه القاعدة', () {
    test('طلبُ المتجرِ يُنشَأ awaiting_payment لا pending', () {
      // لو تغيّر هذا فالقاعدةُ تَحتاجُ مراجعةً لا إسكاتاً.
      expect(storeService.contains("'status': 'awaiting_payment'"), isTrue);
      expect(storeService.contains("'status': 'pending'"), isFalse);
    });
  });
}
