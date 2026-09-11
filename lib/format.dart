const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// 'YYYY-MM-DD', matching the format the server's date columns and API use.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// e.g. "Fri, 5 Sep 2026" — for a DateTime.
String friendlyDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// Same, but for an already-'YYYY-MM-DD' string (what booking rows carry) —
/// falls back to the raw string if it doesn't parse.
String friendlyDateString(String isoDateStr) {
  final parsed = DateTime.tryParse(isoDateStr);
  return parsed == null ? isoDateStr : friendlyDate(parsed);
}

/// changed_at from cleaner_price_history comes back as Postgres's timestamptz,
/// serialized by the JSON driver as an ISO string — parse it and show it in
/// the visitor's local time, e.g. "5 Sep 2026 at 14:30".
String friendlyDateTimeString(String isoDateTimeStr) {
  final parsed = DateTime.tryParse(isoDateTimeStr);
  if (parsed == null) return isoDateTimeStr;
  final local = parsed.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year} at $hh:$mm';
}

/// Formats a price in cents as e.g. "£17" or "£17.50".
String formatMoney(int cents) {
  final pounds = cents / 100;
  return cents % 100 == 0 ? '£${pounds.toStringAsFixed(0)}' : '£${pounds.toStringAsFixed(2)}';
}
