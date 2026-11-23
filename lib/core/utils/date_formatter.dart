import 'package:intl/intl.dart';

class DateFormatter {
  static String toIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime parseIsoDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]) ?? 2026;
      final m = int.tryParse(parts[1]) ?? 1;
      final d = int.tryParse(parts[2]) ?? 1;
      return DateTime(y, m, d);
    }
    return DateTime.now();
  }

  static String formatReadable(String isoDate) {
    try {
      final dt = parseIsoDate(isoDate);
      return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  static String formatMonthYear(int year, int month) {
    final dt = DateTime(year, month, 1);
    try {
      return DateFormat('MMMM yyyy', 'id_ID').format(dt);
    } catch (_) {
      const months = [
        'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
      ];
      return '${months[month - 1]} $year';
    }
  }
}
