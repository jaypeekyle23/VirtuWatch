/// Formats an amount as pesos with thousands separators, e.g. PHP 38,998.
String formatPeso(num amount) {
  final digits = amount.round().toString();
  return 'PHP ${digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
}

/// Formats a date as e.g. Oct 13, 2026.
String formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}