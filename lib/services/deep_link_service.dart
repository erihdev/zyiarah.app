import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';
import 'package:zyiarah/screens/admin/admin_ticket_details_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/screens/order_tracking_screen.dart';
import 'package:zyiarah/screens/contracts_list_screen.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:zyiarah/screens/admin/admin_contracts_screen.dart';
import 'package:zyiarah/utils/notification_target.dart';

class ZyiarahDeepLinkService {
  static final ZyiarahDeepLinkService _instance = ZyiarahDeepLinkService._internal();
  factory ZyiarahDeepLinkService() => _instance;
  ZyiarahDeepLinkService._internal();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  GlobalKey<NavigatorState>? _navKey;

  void initialize(GlobalKey<NavigatorState> navKey) {
    _navKey = navKey;
    _appLinks = AppLinks();

    // 1. Handle initial link (cold start)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleUri(uri);
    });

    // 2. Handle background links
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });
  }

  /// (F1) معالجة النقر على إشعار FCM: تحوّل بيانات الإشعار (orderId/ticketId/requestId)
  /// إلى توجيه عميق فعلي بإعادة استخدام منطق _handleUri نفسه.
  Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    if (data.isEmpty) return;

    // الوجهةُ من القاعدةِ المشتركةِ لا من تعدادٍ هنا: كانت هذه الدالّةُ
    // تَقرأُ `orderId`/`ticketId`/`requestId` وحدَها، فإشعارُ العقدِ — وهو
    // يَحملُ `contractId` — لا يُفتَحُ من أيِّ سطح. (التفصيلُ في
    // `lib/utils/notification_target.dart`.)
    final target = notifTargetFromData(data);
    final String? resource = switch (target.kind) {
      NotifDest.order => 'order',
      NotifDest.support => 'ticket',
      NotifDest.maintenance => 'maintenance',
      NotifDest.contracts => 'contract',
      // بثّ عام (global_broadcast) أو بلا معرّف وجهة → يبقى على الشاشة الحالية
      NotifDest.orders => null,
      NotifDest.offers => null,
      NotifDest.none => null,
    };
    final String? id = target.id;
    if (resource == null || id == null || id.isEmpty) return;

    await _handleUri(Uri.parse('zyiarah://app/$resource/$id'));
  }

  Future<void> _handleUri(Uri uri) async {
    if (uri.scheme != 'zyiarah' || uri.host != 'app') return;

    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) return;

    final String resource = pathSegments[0]; // e.g. 'order', 'ticket', 'maintenance'
    final String? id = pathSegments.length > 1 ? pathSegments[1] : null;
    if (id == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ZyiarahFirebaseService firebaseService = ZyiarahFirebaseService();
    final String role = await firebaseService.getUserRole(user.uid) ?? 'client';
    final bool isAdmin = ['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin', 'admin'].contains(role);
    final bool isDriver = role == 'driver';

    if (resource == 'order') {
       if (isDriver) {
         // السائق يذهب للوحته عبر go_router بدل push شاشة جديدة. الدفع المباشر لـ
         // DriverDashboard على الـ navigator الجذري (نفسه الذي يملكه go_router) كان
         // يكدّس لوحة ثانية فوق الأولى مع سهم رجوع شارد ومزامنة/تتبّع مضاعفَين.
         final ctx = _navKey?.currentContext;
         if (ctx != null && ctx.mounted) GoRouter.of(ctx).go('/driver');
       } else {
         _navKey?.currentState?.push(
           MaterialPageRoute(
             builder: (_) => isAdmin
               ? AdminOrderDetailsScreen(orderId: id)
               : OrderTrackingScreen(orderId: id),
           ),
         );
       }
    } else if (resource == 'ticket') {
       // **كان الفرعُ محصوراً بـ`isAdmin`**، والإشعارُ «تم الرد على تذكرتك 💬»
       // يُرسَلُ إلى **صاحبةِ التذكرة** بـ`{ticketId}` — فنقرُه كان لا يَفعلُ
       // شيئاً، وهو أكثرُ إشعارٍ في التطبيقِ معناه «تعالي اقرئي». شاشةُ الدعمِ
       // تَسردُ تذاكرَها بالردودِ داخلَها، فالوصولُ إليها هو الوجهة.
       if (isAdmin) {
         _navKey?.currentState?.push(
           MaterialPageRoute(builder: (_) => AdminTicketDetailsScreen(ticketId: id))
         );
       } else {
         _navKey?.currentState?.push(
           MaterialPageRoute(builder: (_) => const ZyiarahSupportScreen()),
         );
       }
    } else if (resource == 'contract') {
       // عقدٌ: «تم اعتماد عقدك — أكمِلي الدفع» و«تم تفعيل باقتك» و«جُدوِلت
       // زياراتك». القائمتانِ (العميلةُ والإدارةُ) لا تَأخذانِ معرّفاً، والمعرّفُ
       // يُحمَلُ في الرابطِ كي لا يَضيعَ إن صارتا تَقبلانِه.
       _navKey?.currentState?.push(MaterialPageRoute(
         builder: (_) => isAdmin
             ? const AdminContractsScreen()
             : const ZyiarahContractsListScreen(),
       ));
    } else if (resource == 'maintenance') {
       // **كان فرعاً فارغاً** («For now, let's keep it safe») — فنقرةُ الإشعارِ
       // لا تَفعلُ شيئاً ولا تَقولُ شيئاً، وهو يَقرأ كفرعٍ مُعالَج.
       //
       // صيانةُ الأجهزةِ أُرشِفت (`firestore.rules`: `allow create, update: if
       // false`، ولا موضعَ في المستودعِ يُنشئ مستنداً هناك)، فلا إشعارَ جديدٌ
       // يُولَّد منها عمليّاً — المتبقّي مستنداتٌ قديمةٌ تُقرأ. لكنّ شاشةَ
       // الأرشيفِ **قائمةٌ وتَعملُ**: `AdminOrderDetailsScreen` تَكشف
       // المجموعةَ بنفسِها (`_srcCollection == 'maintenance_requests'`
       // و`_isMaintenanceArchive`) وتُفتَح من شاشةِ البحثِ فعلاً.
       //
       // فالأدمنُ يَذهب إليها، والعميلةُ لا: القراءةُ من `maintenance_requests`
       // محصورةٌ بـ`isAdmin()` في القواعد، فأيُّ دفعٍ لشاشةٍ عميليّةٍ ينتهي
       // بخطأِ صلاحيّات. البقاءُ في مكانِها هو الصواب، مكتوباً لا مسكوتاً عنه.
       if (isAdmin) {
         _navKey?.currentState?.push(
           MaterialPageRoute(builder: (_) => AdminOrderDetailsScreen(orderId: id)),
         );
       }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
