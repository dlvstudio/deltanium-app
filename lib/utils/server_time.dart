/// Server timestamps (Central API, Stores) are UTC, but values read back from MySQL are serialized
/// without a zone ("2026-11-18T09:25:24.38"), and `DateTime.parse` reads those as local time: on a
/// UTC+7 device everything looked 7 hours old and chat times showed in UTC.
/// These helpers read a zoneless date-time as UTC and return it in the device's local time.
/// Date-only values (birthdays) are left as they are.
class ServerTime {
  static final RegExp _hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

  static DateTime? tryParse(String? value) {
    if (value == null) return null;
    final s = value.trim();
    if (s.isEmpty) return null;
    final withZone = (!s.contains('T') || _hasZone.hasMatch(s)) ? s : '${s}Z';
    final dt = DateTime.tryParse(withZone);
    if (dt == null) return null;
    return s.contains('T') ? dt.toLocal() : dt;
  }

  static DateTime parse(String value) =>
      tryParse(value) ?? (throw FormatException('Invalid date-time', value));
}
