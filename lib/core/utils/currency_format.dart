/// Thousands-separated amount formatting (bloc 14): "225415" must always
/// read as "225 415", never as a raw, hard-to-parse number, anywhere an
/// amount is shown - dépenses, prix d'achat, estimation, rapports.
String formatAmount(num amount) {
  final rounded = amount.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return (rounded < 0 ? '-' : '') + buffer.toString();
}

/// Same, with the currency code appended - the display convention used
/// throughout the carnet (e.g. "225 415 DH").
String formatCurrency(num amount, [String currency = 'DH']) {
  return '${formatAmount(amount)} $currency';
}
