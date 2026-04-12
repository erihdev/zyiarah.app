import 'package:cloud_firestore/cloud_firestore.dart';

class ZyiarahExportUtil {
  /// Converts a list of Firestore documents to a CSV string.
  static String convertToCsv(List<DocumentSnapshot> docs) {
    if (docs.isEmpty) return "";

    // Identify all unique keys from all documents to create headers
    Set<String> headers = {};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) headers.addAll(data.keys);
    }

    List<String> headerList = headers.toList();
    headerList.sort(); // Consistent order

    StringBuffer csv = StringBuffer();
    
    // Write Header
    csv.writeln(headerList.join(','));

    // Write Rows
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      List<String> row = [];
      for (var header in headerList) {
        var value = data[header];
        
        // Sanitize value (handle commas and timestamps)
        String valStr = "";
        if (value is Timestamp) {
          valStr = value.toDate().toIso8601String();
        } else if (value == null) {
          valStr = "";
        } else {
          valStr = value.toString().replaceAll(',', ';').replaceAll('\n', ' ');
        }
        
        row.add('"$valStr"');
      }
      csv.writeln(row.join(','));
    }

    return csv.toString();
  }
}
