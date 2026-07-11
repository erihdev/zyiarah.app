import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zyiarah/services/config_service.dart';

class ZyiarahConfigProvider extends ChangeNotifier {
  final ZyiarahConfigService _configService = ZyiarahConfigService();
  StreamSubscription? _uxSubscription;
  
  Color _checkoutButtonColor = const Color(0xFF2563EB); // Default color
  String _checkoutVariantName = "Default";

  Color get checkoutButtonColor => _checkoutButtonColor;
  String get checkoutVariantName => _checkoutVariantName;

  ZyiarahConfigProvider() {
    _init();
  }

  void _init() {
    _uxSubscription = _configService.streamUxExperiments().listen((data) {
      // فحص النوع صراحةً: قيمة غير نصية في مستند التجارب كانت تُسنَد مباشرةً وترمي
      // خطأً غير مُلتقَط داخل المستمع فيتوقّف عن التحديث. onError يحمي من أي فشل بثّ.
      final hex = data['checkout_button_color'];
      if (hex is String && hex.isNotEmpty) {
        _checkoutButtonColor = _configService.getColorFromHex(hex);
      }
      final variant = data['checkout_variant_name'];
      if (variant is String) {
        _checkoutVariantName = variant;
      }
      notifyListeners();
    }, onError: (e) {
      debugPrint('UX experiments stream error: $e');
    });
  }

  @override
  void dispose() {
    _uxSubscription?.cancel();
    super.dispose();
  }
}
