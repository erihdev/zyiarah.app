import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class ZyiarahN8NAutomationService {
  static const String _n8nBaseUrl = "https://n8n.zyiarah.com/webhook";

  static Future<void> triggerAnalyticsEvent({
    required String eventName,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final enrichedPayload = {
        'event': eventName,
        'timestamp': DateTime.now().toIso8601String(),
        'userId': user?.uid ?? 'guest',
        'devicePlatform': 'mobile_app',
        ...payload,
      };

      await http.post(
        Uri.parse('$_n8nBaseUrl/analytics-event'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(enrichedPayload),
      ).timeout(const Duration(seconds: 5));

      unawaited(FirebaseFirestore.instance.collection('analytics_events').add(enrichedPayload));

    } catch (e, stack) {
      debugPrint('Analytics event failed silently: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  static Future<double?> getDynamicPriceSuggestion({
    required String serviceType,
    required double basePrice,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      
      final response = await http.post(
        Uri.parse('$_n8nBaseUrl/ai-pricing-engine'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': user?.uid,
          'serviceType': serviceType,
          'basePrice': basePrice,
          'currentTime': DateTime.now().toIso8601String()
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['optimizedPrice'] != null) {
          return (data['optimizedPrice'] as num).toDouble();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
