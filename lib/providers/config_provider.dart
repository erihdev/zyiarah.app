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
      if (data.containsKey('checkout_button_color')) {
        _checkoutButtonColor = _configService.getColorFromHex(data['checkout_button_color']);
      }
      if (data.containsKey('checkout_variant_name')) {
        _checkoutVariantName = data['checkout_variant_name'];
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _uxSubscription?.cancel();
    super.dispose();
  }
}
