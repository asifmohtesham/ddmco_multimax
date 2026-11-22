enum VariantImageSize {
  off('Off'),
  small('Small'),
  medium('Medium'),
  large('Large');

  const VariantImageSize(this.label);

  final String label;
  static const defaultSize = medium;

  static VariantImageSize fromStorage(Object? value) => values.firstWhere(
    (size) => size.name == value,
    orElse: () => defaultSize,
  );

  double imageHeight({required bool grouped}) => switch (this) {
    off => 0,
    small => 48,
    medium => grouped ? 84 : 200,
    large => 200,
  };

  double get placeholderSize => switch (this) {
    off => 0,
    small => 48,
    medium || large => 54,
  };
}
