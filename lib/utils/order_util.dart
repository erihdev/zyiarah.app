import 'dart:math';

class ZyiarahOrderUtil {
  /// Generates a "Smart Sequential" code: [3 Numbers]-[3 Random Letters]
  /// Example: 101-AFX, 102-KRT
  /// Satisfies the user requirement for short, sequential, and professional IDs.
  static String formatSmartCode(int sequence) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // Pure letters for the 3-letter part
    final rnd = Random();
    
    // Generate 3 random letters
    final letters = String.fromCharCodes(Iterable.generate(
      3, (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
    ));
    
    // Format the number to be at least 3 digits
    String numStr = sequence.toString().padLeft(3, '0');
    
    return '$numStr-$letters';
  }

}
