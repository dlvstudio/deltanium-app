import 'dart:io';

import 'package:flutter/foundation.dart';

class AppLogger {
  static IOSink? _sink;
  static File? _logFile;

  /// Khởi tạo logger, gọi sớm trong hàm main()
  static Future<void> init() async {
    try {
      if (kIsWeb) {
        // ignore: avoid_print
        print('AppLogger: web mode — console only');
        return;
      }

      final logDir = Directory('${Directory.current.path}/appLogs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final logFile = File('${logDir.path}/app-$dateStr.log');
      // ignore: avoid_print
      print('AppLogger: Logging to ${logFile.path}');
      _logFile = logFile;

      _sink = logFile.openWrite(mode: FileMode.append);
      _writeLine('--- Logger started at ${DateTime.now()} ---\n');
    } catch (e) {
      // ignore: avoid_print
      print('AppLogger init failed: $e');
    }
  }

  /// Ghi log ra file (và đồng thời ra console)
  static void log(Object? message) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final formatted = '$timeStr $message';

    // ignore: avoid_print
    print(message);
    _sink?.writeln(formatted);
  }

  /// Đóng file khi app thoát
  static Future<void> dispose() async {
    _writeLine('--- Logger stopped at ${DateTime.now()} ---\n');
    await _sink?.flush();
    await _sink?.close();
  }

  static void _writeLine(String text) {
    _sink?.writeln(text);
  }

  /// Xem file log
  static File? get file => _logFile;
}
