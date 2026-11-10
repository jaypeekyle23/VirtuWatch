/// Where a watch's price sits relative to a customer's saved budget range.
///
/// Budget is an affordability LABEL only. It is deliberately not an input to
/// `scoreWatchAgainstProfile`, so it can never change a watch's match score
/// or its ranking (see the FR-09 note in recommendation_scoring.dart).
enum BudgetStatus { under, within, over }

/// Classifies [price] against [budgetMin]..[budgetMax] (both inclusive, so a
/// price exactly on either edge counts as [BudgetStatus.within]).
BudgetStatus budgetStatus({
  required double price,
  required double budgetMin,
  required double budgetMax,
}) {
  if (price > budgetMax) return BudgetStatus.over;
  if (price < budgetMin) return BudgetStatus.under;
  return BudgetStatus.within;
}

/// How far [price] is above [budgetMax], or 0 when it is at or under it.
/// This is the number behind the "PHP X over budget" text on a watch row.
double amountOverBudget({required double price, required double budgetMax}) {
  final over = price - budgetMax;
  return over > 0 ? over : 0;
}
