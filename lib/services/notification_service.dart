import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zyiarah/services/deep_link_service.dart';

/// خدمة إدارة الإشعارات - تطبيق زيارة
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Background message: ${message.notification?.title}");
}

class ZyiarahNotificationService {
  // Singleton — ضروري حتى يطبّق cleanupOnSignOut/dispose على نفس النسخة العاملة المُهيّأة في main.dart
  static final ZyiarahNotificationService _instance = ZyiarahNotificationService._internal();
  factory ZyiarahNotificationService() => _instance;
  ZyiarahNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'zyiarah_high_importance',
    'إشعارات زيارة',
    description: 'جميع إشعارات تطبيق زيارة المهمة',
    importance: Importance.max,
    playSound: true,
  );

  Future<void> initialize() async {
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await _fcm.getToken();
        if (token != null) await _saveTokenToFirestore(token);
        _tokenRefreshSub = _fcm.onTokenRefresh.listen(_saveTokenToFirestore);
        
        // Subscribe to general topic
        await _fcm.subscribeToTopic('all_users');
        
        // Check auth state for specific topics
        _authStateSub = FirebaseAuth.instance.authStateChanges().listen((User? user) async {
          if (user != null) {
            // أعِد الاشتراك في all_users عند كل دخول — الخروج يُلغيه، وكان يُعاد فقط في
            // initialize() (عند تشغيل التطبيق). فمن يخرج ويدخل بحساب آخر دون إعادة
            // تشغيل كان يبقى خارج all_users فلا يصله بثّ «الكل» كإشعار Push.
            await _fcm.subscribeToTopic('all_users');

            final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
            if (userDoc.exists) {
              final role = userDoc.data()?['role'];
              final adminRoles = ['admin', 'super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin'];
              if (adminRoles.contains(role)) {
                await _fcm.subscribeToTopic('admins');
                await _fcm.unsubscribeFromTopic('clients');
                await _fcm.unsubscribeFromTopic('drivers');
              } else if (role == 'driver') {
                await _fcm.subscribeToTopic('drivers');
                await _fcm.unsubscribeFromTopic('clients');
                await _fcm.unsubscribeFromTopic('admins');
              } else {
                await _fcm.subscribeToTopic('clients');
                await _fcm.unsubscribeFromTopic('drivers');
                await _fcm.unsubscribeFromTopic('admins');
              }
            } else {
                await _fcm.subscribeToTopic('clients');
            }
          }
        });
      }

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings();

      await _localNotifications.initialize(
        const InitializationSettings(android: androidSettings, iOS: iosSettings),
        // (F1) نقر الإشعار المحلي (المعروض أثناء المقدمة) → توجيه عميق
        onDidReceiveNotificationResponse: _onLocalNotificationTap,
      );

      _foregroundMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("Foreground message received: ${message.notification?.title}");
        final n = message.notification;
        // اعرض بانراً محلياً لأي رسالة أمامية تحمل عنواناً. كان مقصوراً على
        // 'new_order_driver' فقط، فكان العميل/السائق داخل التطبيق لا يرى بانر
        // تعيين مهمته أو تأكيد دفعته أو تحديث طلبه — يظهر في الجرس فقط.
        if (n != null) {
          _localNotifications.show(
            message.hashCode,
            n.title,
            n.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _channel.id,
                _channel.name,
                channelDescription: _channel.description,
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
              ),
              iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
            ),
            // (F1) تمرير بيانات الإشعار كي يفتح النقر تفاصيل الطلب
            payload: jsonEncode(message.data),
          );
        }
      });

      // (F1) نقر الإشعار والتطبيق في الخلفية → فتح تفاصيل الطلب
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageTap);

      // (F1) نقر الإشعار والتطبيق مغلق تماماً (cold start)
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleRemoteMessageTap(initialMessage);
      }
    } catch (e) {
      debugPrint("Error initializing notifications: $e");
    }
  }

  /// (F1) معالجة نقر إشعار FCM (خلفية / cold start) عبر التوجيه العميق.
  /// يُؤجَّل لما بعد أول إطار لضمان جاهزية الـ Navigator.
  void _handleRemoteMessageTap(RemoteMessage message) {
    if (message.data.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZyiarahDeepLinkService()
          .handleNotificationTap(Map<String, dynamic>.from(message.data));
    });
  }

  /// (F1) معالجة نقر الإشعار المحلي المعروض أثناء المقدمة.
  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ZyiarahDeepLinkService().handleNotificationTap(data);
      });
    } catch (e) {
      debugPrint("⚠️ Failed to parse local notification payload: $e");
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint("ℹ️ Skip saving FCM token: No user logged in");
        return;
      }

      // Fetch role + staff_role for backend targeting (ADMIN_BROADCAST sub-role routing).
      String role = 'client';
      String? staffRole;
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userDoc.exists) {
          role = userDoc.data()?['role'] ?? 'client';
          staffRole = userDoc.data()?['staff_role'] as String?;
        }
      } catch (e) {
        debugPrint("⚠️ Could not fetch user role for token: $e");
      }

      await FirebaseFirestore.instance.collection('fcm_tokens').doc(uid).set({
        'fcmToken': token, // Backend expects 'fcmToken', not 'token'
        'role': role,      // Added role for administrative broadcasts
        // staff_role: الدور الفرعي الفعلي — يستخدمه توجيه ADMIN_BROADCAST لإيصال
        // تنبيه (مثل عدم تطابق دفع) للمحاسب فقط بدل كل الموظّفين.
        'staff_role': staffRole,
        'updated_at': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      }, SetOptions(merge: true));

      // ملاحظة: رمز FCM خاصّ بالجهاز لا بالحساب. إن سجّل الجهاز سابقاً بحساب آخر
      // ولم يُنظَّف الخروج، يبقى الرمز تحت الحساب القديم فتتسرّب إشعاراته. تنظيف
      // ذلك يتم خادمياً عبر مُشغِّل dedupeFcmToken (لأن قواعد Firestore تمنع
      // العميل من لمس وثيقة رمز حساب آخر).

      debugPrint("✅ FCM Token ($role) saved for user: $uid");
    } catch (e) {
      debugPrint("❌ Error saving FCM token to Firestore: $e");
    }
  }

  /// تنظيف الإشعارات عند تسجيل الخروج.
  /// يجب استدعاؤها *قبل* FirebaseAuth.signOut() لأنها تحتاج uid الحالي.
  /// تمنع وصول إشعارات الحساب السابق إلى هذا الجهاز بعد تبديل الحساب.
  Future<void> cleanupOnSignOut() async {
    // 1) حذف توكن FCM المرتبط بالمستخدم الحالي حتى لا يستقبل الجهاز إشعاراته بعد الخروج
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('fcm_tokens').doc(uid).delete();
      }
    } catch (e) {
      debugPrint("⚠️ Error deleting FCM token doc on sign-out: $e");
    }
    // 2) إلغاء الاشتراك من جميع الـ Topics (سيُعاد الاشتراك حسب دور المستخدم الجديد عند الدخول)
    try {
      await _fcm.unsubscribeFromTopic('all_users');
      await _fcm.unsubscribeFromTopic('clients');
      await _fcm.unsubscribeFromTopic('drivers');
      await _fcm.unsubscribeFromTopic('admins');
    } catch (e) {
      debugPrint("⚠️ Error unsubscribing from FCM topics: $e");
    }
  }

  /// Cancel all stream subscriptions to prevent leaks.
  void dispose() {
    _tokenRefreshSub?.cancel();
    _authStateSub?.cancel();
    _foregroundMessageSub?.cancel();
  }

}
