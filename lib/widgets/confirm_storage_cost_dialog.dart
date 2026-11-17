import 'package:flutter/material.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';

/// Dialog to confirm storage before uploading a post, reaction, comment or message.
///
/// The store node quotes a contract fee (in D). What the wallet is actually charged is decided by
/// Central: uploads inside the free tier cost nothing, beyond it they are billed as paid storage.
/// The dialog reads `/api/wallet/usage` and says which case applies instead of always claiming a deduction.
class ConfirmStorageCostDialog extends StatefulWidget {
  final double totalFee;
  final int durationDays;
  final double costPerDay;
  final int estimatedSizeBytes;
  final String feeBasis;
  final String itemLabel;

  /// Chat: the Store contract reserves space once for the whole conversation; each message is
  /// registered (and counted toward free storage) with its own size.
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
  }) : super(key: key);

  @override
  State<ConfirmStorageCostDialog> createState() => _ConfirmStorageCostDialogState();

  /// Static method to show the dialog
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
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ConfirmStorageCostDialog(
            totalFee: totalFee,
            durationDays: durationDays,
            costPerDay: costPerDay,
            estimatedSizeBytes: estimatedSizeBytes,
            feeBasis: feeBasis,
            itemLabel: itemLabel,
            reservedBundle: reservedBundle,
            onConfirm: onConfirm,
            onCancel: onCancel ?? () {},
          ),
    );
  }
}

class _ConfirmStorageCostDialogState extends State<ConfirmStorageCostDialog> {
  Map<String, dynamic>? _usage;
  bool _usageLoaded = false;

  /// Central's price for a post that is not covered by the free tier (`/api/storedfile/quote`).
  Map<String, dynamic>? _quote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic>? usage;
    Map<String, dynamic>? quote;
    try {
      usage = await WalletService.getUsage();
      if (widget.itemLabel == 'post' && !_coveredByFreeTier(usage)) {
        // Price it before uploading, so a post the wallet cannot pay for is never uploaded.
        quote = await WalletService.quoteStorage(sizeBytes: widget.estimatedSizeBytes, replicas: 1);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _quote = quote;
      _usageLoaded = true;
    });
  }

  bool _coveredByFreeTier(Map<String, dynamic>? usage) {
    final free = usage?['freeTier'] as Map<String, dynamic>?;
    if (free == null || free['eligible'] != true) return false;
    final used = (free['storageUsedBytes'] as num?) ?? 0;
    final quota = (free['storageQuotaBytes'] as num?) ?? 0;
    return used + widget.estimatedSizeBytes <= quota;
  }

  /// Central bills this upload and the wallet cannot pay it: block the upload.
  String? get _blockedReason {
    if (_quote == null || _quote!['enforceFees'] != true) return null;
    final total = ((_quote!['quote'] as Map<String, dynamic>?)?['totalFee'] as num?)?.toDouble() ?? 0;
    final balance = (_usage?['balance'] as num?)?.toDouble() ?? 0;
    if (balance >= total) return null;
    return 'This post needs ${DFormat.full(total)} of paid storage and your balance is ${DFormat.full(balance)}. '
        'Top up from your profile first.';
  }

  String _formatSize(num bytes) {
    if (bytes < 1024) return '${bytes.round()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// The Store quotes its contract fee in D (1 D = 1 VND; minimum 10 D per contract), not DLT.
  String _formatFee(double fee) => fee >= 1 ? DFormat.full(fee) : '${fee.toStringAsFixed(4)} D';

  /// (covered by free tier?, note to show)
  (bool, String) _walletNote() {
    if (!_usageLoaded) return (false, 'Checking your free storage…');
    if (widget.reservedBundle) {
      return (
        true,
        'Free: ${widget.itemLabel}s are never charged to your wallet. Each one counts only its own size '
            'toward your free storage, not the reserved space.',
      );
    }
    final free = _usage?['freeTier'] as Map<String, dynamic>?;
    if (_coveredByFreeTier(_usage)) {
      final used = (free?['storageUsedBytes'] as num?) ?? 0;
      final quota = (free?['storageQuotaBytes'] as num?) ?? 0;
      return (
        true,
        'Covered by your free storage (${_formatSize(used)} of ${_formatSize(quota)} used). '
            'Nothing is deducted from your wallet.',
      );
    }
    if (widget.itemLabel != 'post') {
      // §10: reactions, comments and messages are free even beyond the free storage quota.
      return (true, 'Free: ${widget.itemLabel}s are never charged to your wallet.');
    }
    final blocked = _blockedReason;
    if (blocked != null) return (false, blocked);
    if (_quote != null && _quote!['enforceFees'] != true) {
      return (true, 'Beyond your free storage, but storage fees are not charged on this network yet.');
    }
    final total = ((_quote?['quote'] as Map<String, dynamic>?)?['totalFee'] as num?)?.toDouble();
    if (total != null) {
      return (false, 'Beyond your free storage: ${DFormat.full(total)} is deducted from your wallet for paid storage.');
    }
    final price = (_usage?['storage'] as Map<String, dynamic>?)?['pricePerGbMonth'] ?? 800;
    return (
      false,
      'Beyond your free storage this is billed from your wallet as paid storage '
          '($price D/GB/month per replica).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final (covered, note) = _walletNote();
    final accent = covered ? Colors.green : Colors.orange;
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
            _buildDetailRow('Storage duration:', '${widget.durationDays} days'),
            _buildDetailRow(
              widget.reservedBundle ? 'Reserved space:' : 'Estimated size:',
              _formatSize(widget.estimatedSizeBytes),
            ),
            _buildDetailRow('Node quote:', _formatFee(widget.totalFee)),
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
          onPressed: !_usageLoaded || _blockedReason != null
              ? null
              : () {
            AppLogger.log('User confirmed storage (${widget.itemLabel}): node quote ${widget.totalFee} D');
            widget.onConfirm();
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Text('Confirm & upload', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
