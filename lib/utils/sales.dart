/// Sales history: the rules for what a recorded sale is, and the maths over a
/// list of them. A Dart port of admin-web/src/utils/sales.js. Keep the two in
/// sync, and keep the limits and [paymentMethods] in step with the `sales`
/// block in firestore.rules.
///
/// VirtuWatch has no checkout, payment processing or shipping. A sale happens
/// OFF the platform, so a merchant records it by hand afterwards. Each record
/// keeps a snapshot of the watch's name, brand, photo and price at the time,
/// so editing or deleting a watch later never changes the history.
///
/// A sale is never deleted. A mistake is VOIDED: it stays in the history,
/// marked as voided, and is left out of every total.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

const String saleCompleted = 'completed';
const String saleVoided = 'voided';

/// How the buyer paid, outside the app. Same list as firestore.rules.
const List<String> paymentMethods = [
  'Cash',
  'GCash',
  'Maya',
  'Bank transfer',
  'Card',
  'Other',
];

const int maxSaleQuantity = 99999;
const double maxUnitPrice = 100000000;
const int maxBuyerLength = 120;
const int maxNotesLength = 500;
const int maxVoidReasonLength = 300;

bool isVoidedSale(Map<String, dynamic> sale) => sale['status'] == saleVoided;

/// price x quantity, rounded to centavos so 3 x 1,999.99 never shows a float
/// tail.
double saleTotal(num unitPrice, int quantity) =>
    (unitPrice * quantity * 100).round() / 100;

/// "PHP 12,500". Centavos only appear when there are some.
String formatSaleMoney(num value) {
  final cents = (value * 100).round();
  final whole = (cents ~/ 100).toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  final fraction = cents % 100;
  return fraction == 0
      ? 'PHP $whole'
      : 'PHP $whole.${fraction.toString().padLeft(2, '0')}';
}

// ---------- Dates ----------

/// When the sale happened, or null when there is no date on it.
DateTime? saleDate(Map<String, dynamic> sale) {
  final value = sale['soldAt'];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _endOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// The moment a sale is stamped with, from the day the merchant picked.
/// Today keeps the current time, so sales made on the same day stay in the
/// order they were recorded. Any other day is noon, so a time zone shift can
/// never move it onto a different date.
DateTime soldAtFromDay(DateTime picked, {DateTime? now}) {
  final current = now ?? DateTime.now();
  if (_sameDay(picked, current)) return current;
  return DateTime(picked.year, picked.month, picked.day, 12);
}

enum SalePreset { all, month, last30, year }

String presetLabel(SalePreset preset) => switch (preset) {
      SalePreset.all => 'All time',
      SalePreset.month => 'This month',
      SalePreset.last30 => 'Last 30 days',
      SalePreset.year => 'This year',
    };

/// The from / to days a quick range covers. [SalePreset.all] leaves both open.
({DateTime? from, DateTime? to}) presetRange(SalePreset preset, DateTime now) {
  final today = _startOfDay(now);
  switch (preset) {
    case SalePreset.all:
      return (from: null, to: null);
    case SalePreset.month:
      return (from: DateTime(now.year, now.month, 1), to: today);
    case SalePreset.last30:
      return (from: DateTime(now.year, now.month, now.day - 29), to: today);
    case SalePreset.year:
      return (from: DateTime(now.year, 1, 1), to: today);
  }
}

// ---------- Validation ----------

/// Checks what the "Record a sale" form collected. Returns { field: message };
/// an empty map means it is good to save. [stock] is the watch's current
/// count, or null when the merchant has not entered one (an untracked watch
/// can always be sold).
Map<String, String> validateSaleInput({
  required int? quantity,
  required double? unitPrice,
  required DateTime? soldAt,
  required String paymentMethod,
  String buyerName = '',
  String notes = '',
  int? stock,
  DateTime? now,
}) {
  final errors = <String, String>{};
  final current = now ?? DateTime.now();

  if (quantity == null || quantity < 1) {
    errors['quantity'] = 'Enter at least 1.';
  } else if (quantity > maxSaleQuantity) {
    errors['quantity'] = 'Enter $maxSaleQuantity or fewer.';
  } else if (stock != null && quantity > stock) {
    errors['quantity'] =
        stock == 0 ? 'This watch is out of stock.' : 'Only $stock in stock.';
  }

  if (unitPrice == null || !unitPrice.isFinite || unitPrice <= 0) {
    errors['unitPrice'] = 'Enter the price it sold for.';
  } else if (unitPrice > maxUnitPrice) {
    errors['unitPrice'] = 'That price is too high.';
  }

  if (soldAt == null) {
    errors['soldAt'] = 'Pick the date it was sold.';
  } else if (soldAt.isAfter(_endOfDay(current))) {
    errors['soldAt'] = 'The date cannot be in the future.';
  }

  if (!paymentMethods.contains(paymentMethod)) {
    errors['paymentMethod'] = 'Choose how it was paid.';
  }
  if (buyerName.length > maxBuyerLength) {
    errors['buyerName'] = 'Keep it under $maxBuyerLength characters.';
  }
  if (notes.length > maxNotesLength) {
    errors['notes'] = 'Keep it under $maxNotesLength characters.';
  }
  return errors;
}

// ---------- Filtering and totals ----------

/// Applies the sales screen's search and filters. All are optional.
///   [search]         matches the watch, brand, buyer or notes
///   [from], [to]     days, both ends included
///   [paymentMethod]  one of [paymentMethods], or null for any
///   [includeVoided]  false hides voided sales
List<Map<String, dynamic>> filterSales(
  Iterable<Map<String, dynamic>> sales, {
  String search = '',
  DateTime? from,
  DateTime? to,
  String? paymentMethod,
  bool includeVoided = false,
}) {
  final query = search.trim().toLowerCase();
  final start = from == null ? null : _startOfDay(from);
  final end = to == null ? null : _endOfDay(to);

  return sales.where((sale) {
    if (!includeVoided && isVoidedSale(sale)) return false;
    if (paymentMethod != null && sale['paymentMethod'] != paymentMethod) {
      return false;
    }
    if (start != null || end != null) {
      final date = saleDate(sale);
      if (date == null) return false;
      if (start != null && date.isBefore(start)) return false;
      if (end != null && date.isAfter(end)) return false;
    }
    if (query.isNotEmpty) {
      final haystack = [
        sale['watchName'],
        sale['watchBrand'],
        sale['buyerName'],
        sale['notes'],
      ].whereType<String>().join(' ').toLowerCase();
      if (!haystack.contains(query)) return false;
    }
    return true;
  }).toList();
}

/// Newest sale first. Sales on the same day keep the order they were
/// recorded in.
List<Map<String, dynamic>> sortSalesNewestFirst(
  Iterable<Map<String, dynamic>> sales,
) {
  int millis(Object? value) => value is Timestamp ? value.millisecondsSinceEpoch : 0;
  final list = sales.toList();
  list.sort((a, b) {
    final byDay = (saleDate(b)?.millisecondsSinceEpoch ?? 0)
        .compareTo(saleDate(a)?.millisecondsSinceEpoch ?? 0);
    if (byDay != 0) return byDay;
    return millis(b['createdAt']).compareTo(millis(a['createdAt']));
  });
  return list;
}

/// Totals for a list of sales. Voided sales are left out of revenue, units and
/// count, and are only counted in `voided`, so a mistake never inflates the
/// numbers.
({double revenue, int units, int count, int voided}) salesTotals(
  Iterable<Map<String, dynamic>> sales,
) {
  var revenue = 0.0;
  var units = 0;
  var count = 0;
  var voided = 0;
  for (final sale in sales) {
    if (isVoidedSale(sale)) {
      voided++;
      continue;
    }
    final total = sale['totalAmount'];
    final quantity = sale['quantity'];
    if (total is num) revenue += total;
    if (quantity is int) units += quantity;
    count++;
  }
  return (
    revenue: (revenue * 100).round() / 100,
    units: units,
    count: count,
    voided: voided,
  );
}
