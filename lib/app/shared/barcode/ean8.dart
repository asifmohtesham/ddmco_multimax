/// EAN-8 checksum validation, shared by the scan pipeline and the stock sheet.
class Ean8 {
  const Ean8._();

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  /// True when [code] is exactly eight digits and the last is the correct
  /// check digit (weights 3,1,3,1,3,1,3 over the first seven digits).
  static bool isValid(String code) {
    if (code.length != 8) return false;
    if (!_digitsOnly.hasMatch(code)) return false;
    return _checkDigitFor(code) == int.parse(code[7]);
  }

  /// Appends the check digit to [code7], the first seven digits of an EAN-8.
  /// Throws [ArgumentError] unless [code7] is exactly seven digits.
  static String withCheckDigit(String code7) {
    if (code7.length != 7 || !_digitsOnly.hasMatch(code7)) {
      throw ArgumentError.value(code7, 'code7', 'must be exactly 7 digits');
    }
    return '$code7${_checkDigitFor(code7)}';
  }

  /// The check digit for the first seven digits of [digits].
  static int _checkDigitFor(String digits) {
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      final digit = int.parse(digits[i]);
      sum += i.isEven ? digit * 3 : digit;
    }
    return (10 - (sum % 10)) % 10;
  }
}
