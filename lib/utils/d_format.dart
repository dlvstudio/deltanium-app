import 'package:deltanium_app/config/constants.dart';
import 'package:intl/intl.dart';

/// Formatting for Deltanium credit.
/// Base unit: D (1 D = 1 VND). Display unit: DLT (1 DLT = 1,000,000 D).
class DFormat {
  static final NumberFormat _d = NumberFormat.decimalPattern('vi_VN');
  static final NumberFormat _dlt = NumberFormat('#,##0.######', 'vi_VN');
  static final NumberFormat _exact = NumberFormat('#,##0.####', 'vi_VN');
  static final NumberFormat _tiny = NumberFormat('#,##0.##########', 'vi_VN');

  /// e.g. `1.250.000 D`
  static String d(num amountD) => '${_d.format(amountD.round())} D';

  /// Exact amount to 0.0001 D, the unit Central bills storage in, e.g. `37,3028 D` or `1 D`.
  /// Amounts below 0.0001 D (bandwidth fees) keep the ledger's 10 decimals, e.g. `0,000038892 D`, never `0 D`.
  /// Use it wherever the user is told what is (or will be) taken from the wallet.
  static String exact(num amountD) =>
      '${(amountD != 0 && amountD.abs() < 0.0001 ? _tiny : _exact).format(amountD)} D';

  /// e.g. `10.000 VND`
  static String vnd(num amountVnd) => '${_d.format(amountVnd.round())} VND';

  /// e.g. `1,25 DLT`
  static String dlt(num amountD) => '${_dlt.format(amountD / AppConstants.dPerDlt)} DLT';

  /// e.g. `1,25 DLT (1.250.000 D)`; below 1 DLT shows D only.
  static String full(num amountD) =>
      amountD.abs() >= AppConstants.dPerDlt ? '${dlt(amountD)} (${d(amountD)})' : d(amountD);
}
