import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';
import 'package:zyiarah/screens/admin/admin_ticket_details_screen.dart';

class ZyiarahDeepLinkService {
  static final ZyiarahDeepLinkService _instance = ZyiarahDeepLinkService._internal();
  factory ZyiarahDeepLinkService() => _instance;
  ZyiarahDeepLinkService._internal();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  GlobalKey<NavigatorState>? _navKey;

  void initialize(GlobalKey<NavigatorState> navKey) {
    _navKey = navKey;
    _appLinks = AppLinks();

    // 1. Handle initial link (cold start)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleUri(uri);
    });

    // 2. Handle background links
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'zyiarah' || uri.host != 'app') return;

    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) return;

    final String resource = pathSegments[0]; // e.g. 'order' or 'ticket'
    final String? id = pathSegments.length > 1 ? pathSegments[1] : null;

    if (id == null) return;

    if (resource == 'order') {
       _navKey?.currentState?.push(
         MaterialPageRoute(builder: (_) => AdminOrderDetailsScreen(orderId: id))
       );
    } else if (resource == 'ticket') {
       _navKey?.currentState?.push(
         MaterialPageRoute(builder: (_) => AdminTicketDetailsScreen(ticketId: id))
       );
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
