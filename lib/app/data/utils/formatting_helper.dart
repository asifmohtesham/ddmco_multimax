import 'package:intl/intl.dart';

class FormattingHelper {
  /// Returns the currency symbol for the given currency code (e.g., 'USD' -> '$').
  static String getCurrencySymbol(String currency) {
    try {
      final format = NumberFormat.currency(name: currency);
      return format.currencySymbol;
    } catch (e) {
      return currency; // Fallback to code if symbol not found
    }
  }

  /// Returns a human-readable relative time string (e.g., "2h ago", "Just now").
  static String getRelativeTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 365) {
        return '${(difference.inDays / 365).floor()}y ago';
      } else if (difference.inDays > 30) {
        return '${(difference.inDays / 30).floor()}mo ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return dateString.split(' ')[0]; // Fallback to date part
    }
  }

  /// Calculates the duration between two timestamps (e.g., "2d 4h", "45m").
  static String getTimeTaken(String creation, String modified) {
    if (creation.isEmpty || modified.isEmpty) return '-';
    try {
      final start = DateTime.parse(creation);
      final end = DateTime.parse(modified);
      final difference = end.difference(start);

      if (difference.isNegative) return '-';

      if (difference.inDays > 0) {
        return '${difference.inDays}d ${difference.inHours % 24}h';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ${difference.inMinutes % 60}m';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ${difference.inSeconds % 60}s';
      } else {
        return '${difference.inSeconds}s';
      }
    } catch (e) {
      return '';
    }
  }

  /// Formats quantity, removing trailing zeros if integer.
  static String formatQty(double? qty) {
    if (qty == null) return '0';
    return qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2);
  }
}