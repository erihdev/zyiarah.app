import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zyiarah/services/config_service.dart';

class ZyiarahConfigProvider extends ChangeNotifier {
  final ZyiarahConfigService _configService = ZyiarahConfigService();
  StreamSubscription? _uxSubscription;
  
  Color _checkoutButtonColor = const Color(0xFF2563EB); // Default color

  Color get checkoutButtonColor => _checkoutButtonColor;

  // `checkoutVariantName` أُزيل: اسمُ نسخةِ التجربةِ كان يُقرأ من Firestore
  // ويُحفَظ ولا يَقرؤه شيء — واسمُ النسخةِ إنّما يُوجَدُ لِيُرفَقَ بقياسِ
  // التحويل، ولا قياسَ هنا. اللونُ وحدَه حيٌّ ويُستعمَل.

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
