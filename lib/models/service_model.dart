import 'package:flutter/material.dart';

class ZyiarahService {
  final String id;
  final String title;
  final String subtitle;
  final String priceText;
  final double basePrice;
  final bool isActive;
  final String iconName;
  final String? imagePath;
  final String routeName;
  final int orderIndex;

  ZyiarahService({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.priceText,
    required this.basePrice,
    required this.isActive,
    required this.iconName,
    this.imagePath,
    required this.routeName,
    required this.orderIndex,
  });

  factory ZyiarahService.fromMap(String id, Map<String, dynamic> data) {
    return ZyiarahService(
      id: id,
      title: data['title'] ?? '',
      subtitle: data['subtitle'] ?? '',
      priceText: data['price_text'] ?? '',
      basePrice: (data['base_price'] ?? 0.0).toDouble(),
      isActive: data['is_active'] ?? true,
      iconName: data['icon_name'] ?? 'help_outline',
      imagePath: data['image_path'],
      routeName: data['route_name'] ?? 'default',
      orderIndex: data['order_index'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'price_text': priceText,
      'base_price': basePrice,
      'is_active': isActive,
      'icon_name': iconName,
      'image_path': imagePath,
      'route_name': routeName,
      'order_index': orderIndex,
    };
  }

  static IconData getIcon(String name) {
    switch (name) {
      case 'access_time_filled':
        return Icons.access_time_filled;
      case 'chair':
        return Icons.chair;
      case 'shopping_basket':
        return Icons.shopping_basket;
      case 'settings_suggest_outlined':
        return Icons.settings_suggest_outlined;
      case 'business_center':
        return Icons.business_center;
      case 'shopping_basket_rounded':
        return Icons.shopping_basket_rounded;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'home_repair_service':
        return Icons.home_repair_service;
      default:
        return Icons.help_outline;
    }
  }
}
