import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// خدمة إدارة الإشعارات - تطبيق زيارة
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Background message: ${message.notification?.title}");
}

class ZyiarahNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

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
        _fcm.onTokenRefresh.listen(_saveTokenToFirestore);
        
        // Subscribe to general topic
        await _fcm.subscribeToTopic('all_users');
        
        // Check auth state for specific topics
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
          if (user != null) {
            // Determine if user is client or driver (you might need logic here based on your app's user roles, 
            // but for simplicity, let's assume if they have the driver app they are a driver, 
            // or we can subscribe them based on a database check.)
            
            // For now, let's subscribe everyone to clients topic unless we have a specific driver verification.
            // In a real app, you'd fetch the user role from Firestore first.
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
            if (userDoc.exists) {
              final role = userDoc.data()?['role'];
              if (role == 'admin') {
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
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showLocalNotification(message);
      });
    } catch (e) {
      debugPrint("Error initializing notifications: $e");
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint("ℹ️ Skip saving FCM token: No user logged in");
        return;
      }

      await FirebaseFirestore.instance.collection('fcm_tokens').doc(uid).set({
        'token': token,
        'updated_at': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      }, SetOptions(merge: true));

      debugPrint("✅ FCM Token saved for user: $uid");
    } catch (e) {
      debugPrint("❌ Error saving FCM token to Firestore: $e");
    }
  }


  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
