import 'package:flutter/material.dart';
import 'package:deltanium_app/services/app_logger.dart';

/// Dialog to confirm storage costs before uploading post
class ConfirmStorageCostDialog extends StatelessWidget {
  final double totalFee;
  final int durationDays;
  final double costPerDay;
  final int estimatedSizeBytes;
  final String feeBasis;
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
  }) : super(key: key);

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Format fee so very small values (e.g. 0.0000001648) don't show as "0.00000 DLT".
  String _formatFee(double fee) {
    if (fee == 0) return '0 DLT';
    if (fee >= 0.0001) return '${fee.toStringAsFixed(5)} DLT';
    if (fee >= 0.0000001) return '${fee.toStringAsFixed(10)} DLT';
    return '${fee.toStringAsExponential(4)} DLT';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Storage Cost'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your post will be stored with the following terms:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            
            // Storage details
            _buildDetailRow('Storage Duration:', '$durationDays days'),
            _buildDetailRow('Estimated Size:', _formatSize(estimatedSizeBytes)),
            _buildDetailRow('Unit Cost:', _formatFee(costPerDay) + '/day'),
            
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            
            // Total cost - highlighted
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Storage Cost:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatFee(totalFee),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    feeBasis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Warning
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: const Text(
                '⚠️ This cost will be deducted from your account upon confirmation.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            AppLogger.log('User cancelled storage cost confirmation');
            onCancel();
            Navigator.of(context).pop();
          },
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.red),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            AppLogger.log('User confirmed storage cost: $totalFee DLT');
            onConfirm();
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
          ),
          child: const Text(
            'Confirm & Upload',
            style: TextStyle(color: Colors.white),
          ),
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
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

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
        onConfirm: onConfirm,
        onCancel: onCancel ?? () {},
      ),
    );
  }
}
