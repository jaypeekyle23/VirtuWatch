/// How many units of a watch are left, and what that means for the UI.
///
/// This is the ONE definition of "low" and "out of stock". The tile badges,
/// the detail screens, the merchant alerts and the chatbot prompts all call
/// the functions here, so they can never disagree.
///
/// A watch document keeps its count in one whole-number field:
///
///   stock: 5
///
/// A missing or null `stock` means the seller has not entered a count yet.
/// That is NOT the same as zero. Watches listed before this feature existed
/// have no `stock`, and they must not suddenly show as sold out.
///
/// There is no checkout in VirtuWatch, so nothing lowers the count by
/// itself. The merchant types it in, or uses the stock dialog, and edits it
/// as they sell.
library;

/// At this many units or fewer (but more than zero), a watch counts as low.
const int lowStockThreshold = 3;

enum StockStatus {
  /// The seller has not entered a count for this watch.
  untracked,
  inStock,
  low,
  out,
}

/// The saved count, or null when none is on file. A negative number (which
/// the form never writes) is read as zero.
int? stockOf(Map<String, dynamic> data) {
  final value = data['stock'];
  if (value is! num) return null;
  final count = value.toInt();
  return count < 0 ? 0 : count;
}

StockStatus stockStatus(Map<String, dynamic> data) {
  final count = stockOf(data);
  if (count == null) return StockStatus.untracked;
  if (count == 0) return StockStatus.out;
  if (count <= lowStockThreshold) return StockStatus.low;
  return StockStatus.inStock;
}

bool isOutOfStock(Map<String, dynamic> data) =>
    stockStatus(data) == StockStatus.out;

bool isLowStock(Map<String, dynamic> data) =>
    stockStatus(data) == StockStatus.low;

/// True when the seller says there is at least one unit on hand (in stock or
/// low). A watch with no count on file is NOT counted, since its availability
/// is unknown.
bool isInStock(Map<String, dynamic> data) {
  final status = stockStatus(data);
  return status == StockStatus.inStock || status == StockStatus.low;
}

/// True for a watch the merchant should look at: low or out.
bool needsStockAttention(Map<String, dynamic> data) {
  final status = stockStatus(data);
  return status == StockStatus.low || status == StockStatus.out;
}

/// What a customer reads: "12 in stock", "Only 2 left" or "Out of stock".
/// Null when no count is on file, so the UI shows nothing instead of
/// guessing.
String? customerStockLabel(Map<String, dynamic> data) {
  final count = stockOf(data);
  switch (stockStatus(data)) {
    case StockStatus.untracked:
      return null;
    case StockStatus.out:
      return 'Out of stock';
    case StockStatus.low:
      return count == 1 ? 'Only 1 left' : 'Only $count left';
    case StockStatus.inStock:
      return '$count in stock';
  }
}

/// What a merchant reads: the real number.
String? merchantStockLabel(Map<String, dynamic> data) {
  final count = stockOf(data);
  switch (stockStatus(data)) {
    case StockStatus.untracked:
      return null;
    case StockStatus.out:
      return 'Out of stock';
    case StockStatus.low:
      return 'Low: $count left';
    case StockStatus.inStock:
      return '$count in stock';
  }
}

/// One phrase for the chatbot prompts, with the same count customers see.
String stockPromptLine(Map<String, dynamic> data) {
  final count = stockOf(data);
  switch (stockStatus(data)) {
    case StockStatus.untracked:
      return 'Availability: NOT on file (the seller has not entered stock for this watch)';
    case StockStatus.out:
      return 'Availability: OUT OF STOCK';
    case StockStatus.low:
      return 'Availability: LOW STOCK (only $count left)';
    case StockStatus.inStock:
      return 'Availability: in stock ($count available)';
  }
}

/// How many of [watches] are out of stock and how many are running low.
({int out, int low}) stockAlertCounts(Iterable<Map<String, dynamic>> watches) {
  var out = 0;
  var low = 0;
  for (final data in watches) {
    switch (stockStatus(data)) {
      case StockStatus.out:
        out++;
      case StockStatus.low:
        low++;
      case StockStatus.inStock:
      case StockStatus.untracked:
        break;
    }
  }
  return (out: out, low: low);
}

/// Sort key for alert lists: out of stock first, then the fewest left.
int compareByStockUrgency(Map<String, dynamic> a, Map<String, dynamic> b) =>
    (stockOf(a) ?? 0).compareTo(stockOf(b) ?? 0);
