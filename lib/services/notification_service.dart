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
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // We skip showing local notification banners while the app is in foreground
        // as requested to follow modern minimalist app standards. 
        // Real-time status updates are handled via Firestore listeners in the UI.
        debugPrint("Foreground message received: ${message.notification?.title}");
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

      // Fetch user role to include it in the token document for backend targeting
      String role = 'client';
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userDoc.exists) {
          role = userDoc.data()?['role'] ?? 'client';
        }
      } catch (e) {
        debugPrint("⚠️ Could not fetch user role for token: $e");
      }

      await FirebaseFirestore.instance.collection('fcm_tokens').doc(uid).set({
        'fcmToken': token, // Backend expects 'fcmToken', not 'token'
        'role': role,      // Added role for administrative broadcasts
        'updated_at': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      }, SetOptions(merge: true));

      debugPrint("✅ FCM Token ($role) saved for user: $uid");
    } catch (e) {
      debugPrint("❌ Error saving FCM token to Firestore: $e");
    }
  }

}
