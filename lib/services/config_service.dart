import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ZyiarahConfigService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<Map<String, dynamic>> streamUxExperiments() {
    return _db.collection('config').doc('ux_experiments').snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
      return {};
    });
  }

  Color getColorFromHex(String hexColor) {
    hexColor = hexColor.replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    return Color(int.parse(hexColor, radix: 16));
  }
}
