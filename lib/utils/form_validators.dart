/// Validates a required numeric field that must be a positive value —
/// Price and Lug-to-Lug on the merchant add/edit watch forms. Rejects
/// blank input, non-numeric input, and zero/negative values (a
/// negative price or a zero lug-to-lug measurement is never valid for
/// a physical watch).
String? requiredPositiveNumber(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  final parsed = double.tryParse(value.trim());
  if (parsed == null) return 'Enter a valid number';
  if (parsed <= 0) return 'Must be greater than 0';
  return null;
}

/// Validates an optional numeric field — Case Diameter, Case Thickness,
/// Band Width — where leaving it blank is fine, but anything actually
/// entered must be a valid, positive number. Without this, garbage
/// input (e.g. a typo) previously passed validation silently and was
/// then dropped as `null` on save via `double.tryParse`, giving the
/// merchant no indication their input didn't take.
String? optionalPositiveNumber(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = double.tryParse(value.trim());
  if (parsed == null) return 'Enter a valid number';
  if (parsed <= 0) return 'Must be greater than 0';
  return null;
}