import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/utils/global_error_handler.dart';

class ZyiarahN8NAutomationService {
  static const String _n8nBaseUrl = "https://n8n.zyiarah.com/webhook"; // Replace with your actual n8n instance

  /// Emits an event to n8n for A/B Testing, Cart Abandonment, or Predictive Marketing.
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

      // Asynchronously log to firestore for local audits
      FirebaseFirestore.instance.collection('analytics_events').add(enrichedPayload);

    } catch (e) {
      // Non-fatal, just log silently because analytics should never block the UI
      GlobalErrorHandler.handleError(e);
    }
  }

  /// Queries the n8n AI engine for optimal dynamic pricing based on user history and demand.
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
      // If AI engine is offline or timeout, fallback natively
      return null;
    }
  }
}
