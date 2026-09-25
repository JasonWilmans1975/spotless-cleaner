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

// ---- Shared with the customer app (spotless-customer/lib/format.dart) ----

const _fullMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

/// e.g. "Tue, 29 Sep" — no year, for cards where the year is obvious.
String shortDate(DateTime d) => '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]}';

/// e.g. "September 2026".
String monthYear(DateTime d) => '${_fullMonthNames[d.month - 1]} ${d.year}';

/// e.g. "22 Sep, 14:21".
String dayMonthTime(DateTime d) =>
    '${d.day} ${_monthNames[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Whole calendar days from [today] to [day] (0 = today), unaffected by clock changes.
int daysUntil(DateTime day, DateTime today) => DateTime.utc(day.year, day.month, day.day)
    .difference(DateTime.utc(today.year, today.month, today.day))
    .inDays;

/// 'HH:MM' -> minutes since midnight (0 if it doesn't parse).
int toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

/// Minutes as "1 hour", "3 hours" or "1h 30m".
String durationText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (m != 0) return h == 0 ? '${m}m' : '${h}h ${m}m';
  return h == 1 ? '1 hour' : '$h hours';
}
