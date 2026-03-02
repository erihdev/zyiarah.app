import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// خدمة إدارة الإشعارات - تطبيق زيارة
class ZyiarahNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// تهيئة نظام الإشعارات
  Future<void> initialize() async {
    // 1. طلب تصريح من المستخدم (خاصة في iOS 13+)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. الحصول على رمز الجهاز (Token) لإرسال إشعارات مخصصة لهذا المستخدم
      String? token = await _fcm.getToken();
      print("Device Token: $token"); // يفضل حفظه في Firestore تحت بيانات المستخدم
    }

    // 3. إعداد الإشعارات المحلية لإظهارها أثناء فتح التطبيق (Foreground)
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // 4. الاستماع للإشعارات أثناء فتح التطبيق
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });
  }

  /// عرض إشعار منبثق للمستخدم
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'zyiarah_channel',
      'إشعارات زيارة',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      const NotificationDetails(android: androidDetails),
    );
  }
}
