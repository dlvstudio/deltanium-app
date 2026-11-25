import 'dart:async';

import 'package:flutter/material.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';

/// One line of what an upload costs, e.g. ("Image photo.png", 37.3028).
typedef StorageChargeLine = ({String label, double charge});

/// Asks the user to confirm Central's exact [charge] for one uploaded file; true when confirmed.
Future<bool> confirmStorageCharge(
  BuildContext context, {
  required String fileName,
  required int sizeBytes,
  required double charge,
  String itemLabel = 'file',
}) {
  final completer = Completer<bool>();
  ConfirmStorageCostDialog.show(
    context: context,
    totalFee: charge,
    durationDays: 365,
    costPerDay: charge / 365,
    estimatedSizeBytes: sizeBytes,
    feeBasis: '',
    itemLabel: itemLabel,
    breakdown: [(label: fileName, charge: charge)],
    onConfirm: () => completer.complete(true),
    onCancel: () => completer.complete(false),
  );
  return completer.future;
}

/// Confirms what an upload (post, attachments, reaction, comment, message, file) takes from the wallet.
///
/// [totalFee] is Central's exact charge (`GET /api/storedfile/quote` → `charge`, whole 0.0001 D) for everything
/// this upload registers, the same amount registration then deducts. The dialog shows it to 4 decimals, so the
/// D shown is the D paid; it never shows a Store's own quote. Upload is blocked when the balance is short.
class ConfirmStorageCostDialog extends StatefulWidget {
  final double totalFee;
  final int durationDays;
  final double costPerDay;
  final int estimatedSizeBytes;
  final String feeBasis;
  final String itemLabel;

  /// Per-item charges summing to [totalFee] (a post with attachments); empty shows the total only.
  final List<StorageChargeLine> breakdown;

  /// Chat: the Store contract reserves space once for the whole conversation; each message is
  /// registered and billed by Central on its own.
  final bool reservedBundle;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const ConfirmStorageCostDialog({
    Key? key,
    required this.totalFee,
    required this.durationDays,
    required this.costPerDay,
    required this.estimatedSizeBytes,
    required this.feeBasis,
    required this.onConfirm,
    required this.onCancel,
    this.itemLabel = 'post',
    this.reservedBundle = false,
    this.breakdown = const [],
  }) : super(key: key);

  @override
  State<ConfirmStorageCostDialog> createState() => _ConfirmStorageCostDialogState();

  static void show({
    required BuildContext context,
    required double totalFee,
    required int durationDays,
    required double costPerDay,
    required int estimatedSizeBytes,
    required String feeBasis,
    required VoidCallback onConfirm,
    VoidCallback? onCancel,
    String itemLabel = 'post',
    bool reservedBundle = false,
    List<StorageChargeLine> breakdown = const [],
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConfirmStorageCostDialog(
        totalFee: totalFee,
        durationDays: durationDays,
        costPerDay: costPerDay,
        estimatedSizeBytes: estimatedSizeBytes,
        feeBasis: feeBasis,
        itemLabel: itemLabel,
        reservedBundle: reservedBundle,
        breakdown: breakdown,
        onConfirm: onConfirm,
        onCancel: onCancel ?? () {},
      ),
    );
  }
}

class _ConfirmStorageCostDialogState extends State<ConfirmStorageCostDialog> {
  double? _balance;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    double? balance;
    try {
      if (widget.totalFee > 0) balance = await WalletService.getBalance();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _loaded = true;
    });
  }

  bool get _short => widget.totalFee > 0 && _balance != null && _balance! < widget.totalFee;

  String _formatSize(num bytes) {
    if (bytes < 1024) return '${bytes.round()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  (bool ok, String note) _note() {
    if (widget.totalFee <= 0) {
      return (true, 'Free: nothing is deducted from your wallet.');
    }
    if (!_loaded) return (false, 'Checking your balance…');
    final total = DFormat.exact(widget.totalFee);
    if (_short) {
      return (
        false,
        'This needs $total and your balance is ${DFormat.exact(_balance!)}. Top up from your profile first.',
      );
    }
    final after = _balance == null ? '' : ' Balance after: ${DFormat.exact(_balance! - widget.totalFee)}.';
    return (false, 'Exactly $total is deducted from your wallet when you confirm.$after');
  }

  @override
  Widget build(BuildContext context) {
    final (free, note) = _note();
    final accent = free ? Colors.green : (_short ? Colors.red : Colors.orange);
    return AlertDialog(
      title: const Text('Confirm storage'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.reservedBundle
                  ? 'This conversation reserves space on a storage node for its ${widget.itemLabel}s:'
                  : 'Your ${widget.itemLabel} will be stored with the following terms:',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            _row('Storage duration:', '${widget.durationDays} days'),
            if (widget.estimatedSizeBytes > 0)
              _row(widget.reservedBundle ? 'Reserved space:' : 'Size:', _formatSize(widget.estimatedSizeBytes)),
            for (final l in widget.breakdown) _row(l.label, DFormat.exact(l.charge)),
            _row('You pay:', DFormat.exact(widget.totalFee), bold: true),
            if (widget.feeBasis.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.feeBasis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent, width: 1),
              ),
              child: Text(note, style: TextStyle(fontSize: 12, color: accent, height: 1.35)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            AppLogger.log('User cancelled storage confirmation (${widget.itemLabel})');
            widget.onCancel();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: (widget.totalFee > 0 && !_loaded) || _short
              ? null
              : () {
                  AppLogger.log('User confirmed storage (${widget.itemLabel}): ${widget.totalFee} D');
                  widget.onConfirm();
                  Navigator.of(context).pop();
                },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Text('Confirm & upload', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          const SizedBox(width: 12),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        ],
      ),
    );
  }
}
