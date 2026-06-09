import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class TimeService {
  TimeService._();

  static const _mytOffset = Duration(hours: 8);

  /// Returns the current date and time in Malaysia Time (MYT, UTC+8).
  /// Does NOT rely on the device's local timezone.
  static DateTime nowMYT() {
    final utc = DateTime.now().toUtc();
    final myt = utc.add(_mytOffset);
    debugPrint('[TimeService] nowMYT: Local=${DateTime.now()} '
        'UTC=$utc MYT=$myt');
    return myt;
  }

  /// Converts a [DateTime] known to be in UTC to Malaysia Time (MYT, UTC+8).
  ///
  /// Always interprets the input as UTC (regardless of `isUtc` flag) and
  /// adds the +8h offset.
  static DateTime toMYT(DateTime dt) {
    final myt = dt.add(_mytOffset);
    debugPrint('[TimeService] toMYT: input=$dt isUtc=${dt.isUtc} MYT=$myt');
    return myt;
  }

  /// Parses an ISO-8601 string and returns the equivalent MYT [DateTime].
  ///
  /// If the string ends with `Z` it is treated as UTC first.
  /// Otherwise the string is assumed to already represent MYT.
  static DateTime parseToMYT(String input) {
    try {
      final dt = DateTime.parse(input);
      debugPrint('[TimeService] parseToMYT: input=$input '
          'parsed=$dt isUtc=${dt.isUtc}');
      if (dt.isUtc || input.endsWith('Z') || input.contains('+00:00')) {
        // String was UTC → add 8h for MYT
        final myt = dt.add(_mytOffset);
        debugPrint('[TimeService] parseToMYT: UTC→MYT $myt');
        return myt;
      }
      // Already in MYT (or no timezone info)
      debugPrint('[TimeService] parseToMYT: assumed already MYT $dt');
      return dt;
    } catch (e) {
      debugPrint('[TimeService] parseToMYT: error "$e" for input "$input"');
      return nowMYT();
    }
  }

  // ---- Format helpers (input can be DateTime or String) ----

  /// yyyy-MM-dd
  static String formatDate(dynamic input) {
    final dt = _resolve(input);
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  /// yyyy-MM-dd HH:mm
  static String formatDateTime(dynamic input) {
    final dt = _resolve(input);
    return DateFormat('yyyy-MM-dd HH:mm').format(dt) + ' MYT';
  }

  /// HH:mm
  static String formatTime(dynamic input) {
    final dt = _resolve(input);
    return DateFormat('HH:mm').format(dt);
  }

  /// Tuesday, 9 June 2026
  static String formatDateLong(dynamic input) {
    final dt = _resolve(input);
    return DateFormat('EEEE, d MMMM yyyy').format(dt);
  }

  /// dd/MM/yyyy HH:mm
  static String formatDateTimeShort(dynamic input) {
    final dt = _resolve(input);
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  /// dd/MM/yyyy
  static String formatDateShort(dynamic input) {
    final dt = _resolve(input);
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  /// Relative human-friendly: "Just now", "5m ago", "3h ago", "2d ago"
  static String formatRelative(dynamic input) {
    final dt = _resolve(input);
    final now = nowMYT();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  /// Mon .. Sun
  static String getDayOfWeekName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return '';
    }
  }

  /// Jan .. Dec
  static String getMonthName(int month) {
    int normalized = month;
    while (normalized <= 0) normalized += 12;
    while (normalized > 12) normalized -= 12;
    switch (normalized) {
      case 1:
        return 'Jan';
      case 2:
        return 'Feb';
      case 3:
        return 'Mar';
      case 4:
        return 'Apr';
      case 5:
        return 'May';
      case 6:
        return 'Jun';
      case 7:
        return 'Jul';
      case 8:
        return 'Aug';
      case 9:
        return 'Sep';
      case 10:
        return 'Oct';
      case 11:
        return 'Nov';
      case 12:
        return 'Dec';
      default:
        return '';
    }
  }

  /// Custom format using [DateFormat] pattern string.
  /// Example: `formatCustom(input, 'dd/MM')` → "09/06"
  static String formatCustom(dynamic input, String pattern) {
    final dt = _resolve(input);
    return DateFormat(pattern).format(dt);
  }

  /// Resolve a dynamic input (String | DateTime) into a MYT DateTime.
  ///
  /// - [DateTime]: assumed to already be in MYT — returned as-is.
  /// - [String]:   parsed via [parseToMYT] (handles both UTC/Z and MYT strings).
  /// - Other:      falls back to [nowMYT].
  static DateTime _resolve(dynamic input) {
    if (input is DateTime) return input;
    if (input is String && input.isNotEmpty) return parseToMYT(input);
    return nowMYT();
  }
}
