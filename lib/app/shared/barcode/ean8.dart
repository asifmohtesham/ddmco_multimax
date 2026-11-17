/// EAN-8 checksum validation, shared by the scan pipeline and the stock sheet.
class Ean8 {
  const Ean8._();

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  /// True when [code] is exactly eight digits and the last is the correct
  /// check digit (weights 3,1,3,1,3,1,3 over the first seven digits).
  static bool isValid(String code) {
    if (code.length != 8) return false;
    if (!_digitsOnly.hasMatch(code)) return false;

    var sum = 0;
    for (var i = 0; i < 7; i++) {
      final digit = int.parse(code[i]);
      sum += i.isEven ? digit * 3 : digit;
    }
    return (10 - (sum % 10)) % 10 == int.parse(code[7]);
  }
}
