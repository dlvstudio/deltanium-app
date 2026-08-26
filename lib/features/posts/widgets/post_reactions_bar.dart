import 'dart:async';
import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/services/reaction_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/widgets/confirm_storage_cost_dialog.dart';

class PostReactionsBar extends StatefulWidget {
  final PostMetadata post;
  final String nodeEndpoint;
  final bool isDarkMode;
  final String? userPublicKey;
  final String? userMnemonic;

  const PostReactionsBar({
    Key? key,
    required this.post,
    required this.nodeEndpoint,
    required this.isDarkMode,
    this.userPublicKey,
    this.userMnemonic,
  }) : super(key: key);

  @override
  State<PostReactionsBar> createState() => _PostReactionsBarState();
}

class _PostReactionsBarState extends State<PostReactionsBar> {
  String? _myReaction;
  int _reactionCount = 0;
  bool _isLoading = false;
  Map<String, dynamic> _byKind = {}; // Store counts by reaction kind

  @override
  void initState() {
    super.initState();
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    if (widget.userPublicKey == null || widget.userMnemonic == null) {
      return;
    }
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await ReactionService.getReactions(
        postFileId: widget.post.fileId,
        nodeEndpoint: widget.nodeEndpoint,
        userPublicKey: widget.userPublicKey!,
        userMnemonic: widget.userMnemonic!,
      );

      if (result != null && mounted) {
        // Handle both camelCase and PascalCase from API
        final total = (result['Total'] ?? result['total']) as int? ?? 0;
        final myReaction = (result['MyReaction'] ?? result['myReaction']) as String?;
        final byKind = (result['ByKind'] ?? result['byKind']) as Map<String, dynamic>? ?? {};
        
        AppLogger.log('PostReactionsBar: Loaded reactions for ${widget.post.fileId.substring(0, 8)}... - total=$total, myReaction=$myReaction, byKind=$byKind');
        
        // Use total count for display (Facebook-style shows total)
        setState(() {
          _reactionCount = total;
          _myReaction = myReaction;
          _byKind = byKind;
          _isLoading = false;
        });
      } else if (mounted) {
        AppLogger.log('PostReactionsBar: No reactions data returned for ${widget.post.fileId.substring(0, 8)}...');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('PostReactionsBar: Error loading reactions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get all reactions with count > 0, sorted by count (descending)
    final activeReactions = _getActiveReactions();
    
    if (activeReactions.isEmpty) {
      // No reactions yet - show default icon
      return InkWell(
        onTap: _openReactionPicker,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border,
              size: 20,
              color: widget.isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              '0',
              style: TextStyle(
                fontSize: 14,
                color: widget.isDarkMode
                    ? DeltaniumTheme.darkTextSecondaryColor
                    : DeltaniumTheme.lightTextSecondaryColor,
              ),
            ),
          ],
        ),
      );
    }

    // Facebook-style: show all reaction icons + total count
    return InkWell(
      onTap: _openReactionPicker,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show up to 3 reaction icons (most popular ones)
          ...activeReactions.take(3).map((entry) {
            final kind = entry['kind'] as String;
            final isMyReaction = _myReaction == kind;
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                _reactionIconFor(kind),
                size: 18,
                color: isMyReaction
                    ? Colors.pinkAccent
                    : (widget.isDarkMode
                        ? DeltaniumTheme.darkTextSecondaryColor
                        : DeltaniumTheme.lightTextSecondaryColor),
              ),
            );
          }),
          // If more than 3 reactions, show "+" indicator
          if (activeReactions.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 4),
              child: Text(
                '+${activeReactions.length - 3}',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
            ),
          const SizedBox(width: 4),
          // Show total count
          Text(
            _reactionCount.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: widget.isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Get active reactions sorted by count (descending)
  List<Map<String, dynamic>> _getActiveReactions() {
    if (_byKind.isEmpty) return [];
    
    final List<Map<String, dynamic>> reactions = [];
    _byKind.forEach((kind, count) {
      final countInt = (count as num?)?.toInt() ?? 0;
      if (countInt > 0) {
        reactions.add({
          'kind': kind,
          'count': countInt,
        });
      }
    });
    
    // Sort by count descending, then by kind for consistency
    reactions.sort((a, b) {
      final countA = a['count'] as int;
      final countB = b['count'] as int;
      if (countA != countB) {
        return countB.compareTo(countA); // Descending
      }
      return (a['kind'] as String).compareTo(b['kind'] as String);
    });
    
    return reactions;
  }

  void _openReactionPicker() async {
    final reactions = ReactionService.supportedReactions;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ...reactions.map((kind) {
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_reactionIconFor(kind), size: 18),
                        const SizedBox(width: 6),
                        Text(_reactionLabel(kind)),
                      ],
                    ),
                    selected: _myReaction == kind,
                    onSelected: (_) => Navigator.of(context).pop(kind),
                  );
                }).toList(),
                if (_myReaction != null)
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 16),
                    label: const SizedBox.shrink(),
                    tooltip: 'Bỏ react',
                    onPressed: () => Navigator.of(context).pop('__remove__'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen == null) return;
    if (chosen == '__remove__') {
      await _removeReaction();
      return;
    }
    await _applyReaction(chosen);
  }

  Future<void> _applyReaction(String kind) async {
    if (widget.userPublicKey == null || widget.userMnemonic == null) {
      return;
    }

    // Pre-generate IDs early so they can be included in the contract
    final ids = ReactionService.generateIds();
    final fileId = ids['fileId']!;
    final firstBlockId = ids['firstBlockId']!;

    // Step 1: Prepare contract and get fee info
    final storageInfo = await ReactionService.prepareReactionWithStorageCost(
      nodeEndpoint: widget.nodeEndpoint,
      userPublicKey: widget.userPublicKey!,
      userMnemonic: widget.userMnemonic!,
      storageNodePublicKey: '', // Store fills its own key
      fileId: fileId,
    );

    if (storageInfo['success'] != true) {
      AppLogger.log('PostReactionsBar: Failed to prepare storage cost: ${storageInfo['error']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to prepare reaction: ${storageInfo['error']}')),
        );
      }
      return;
    }

    final totalFee = (storageInfo['totalFee'] as num?)?.toDouble() ?? 0.0;
    final contractId = storageInfo['contractId'] as String?;

    // Step 2: Show fee confirmation (skip if free/zero)
    bool confirmed = totalFee <= 0;
    if (!confirmed && mounted) {
      final completer = Completer<bool>();
      ConfirmStorageCostDialog.show(
        context: context,
        totalFee: totalFee,
        durationDays: storageInfo['durationDays'] as int? ?? 365,
        costPerDay: (storageInfo['estimatedCostPerDay'] as num?)?.toDouble() ?? 0.0,
        estimatedSizeBytes: storageInfo['estimatedSize'] as int? ?? 500,
        feeBasis: storageInfo['feeBasis'] as String? ?? 'Reaction storage fee',
        onConfirm: () => completer.complete(true),
        onCancel: () => completer.complete(false),
      );
      confirmed = await completer.future;
    }

    if (!confirmed) return;

    // Step 3: Sign contract
    if (contractId != null) {
      final signed = await ReactionService.signContract(
        nodeEndpoint: widget.nodeEndpoint,
        contractId: contractId,
        userPublicKey: widget.userPublicKey!,
        userMnemonic: widget.userMnemonic!,
        storageNodePublicKey: '',
        totalFee: totalFee,
        totalFileSize: storageInfo['estimatedSize'] as int? ?? 500,
        startDateUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      if (!signed) {
        AppLogger.log('PostReactionsBar: Failed to sign contract');
        return;
      }
    }

    // Step 4: Apply reaction with contract
    final wasReacted = _myReaction != null;
    setState(() {
      _myReaction = kind;
      _reactionCount = (_reactionCount <= 0 ? 0 : _reactionCount) + (wasReacted ? 0 : 1);
    });
    final ok = await ReactionService.sendReaction(
      postFileId: widget.post.fileId,
      nodeEndpoint: widget.nodeEndpoint,
      reactionKind: kind,
      userPublicKey: widget.userPublicKey!,
      userMnemonic: widget.userMnemonic!,
      postOwnerPublicKey: widget.post.ownerPubKey,
      postEncryptedType: widget.post.encryptedType,
      contractId: contractId,
      fileId: fileId,
      firstBlockId: firstBlockId,
    );
    if (!ok) {
      setState(() {
        if (!wasReacted) {
          _reactionCount = (_reactionCount > 0) ? _reactionCount - 1 : 0;
        }
        _myReaction = wasReacted ? _myReaction : null;
      });
    } else {
      await _loadReactions();
    }
  }

  Future<void> _removeReaction() async {
    if (widget.userPublicKey == null || widget.userMnemonic == null) {
      return;
    }
    if (_myReaction == null) return;
    final previousKind = _myReaction;
    final previousCount = _reactionCount;
    setState(() {
      _myReaction = null;
      _reactionCount = (_reactionCount > 0) ? _reactionCount - 1 : 0;
    });
    final ok = await ReactionService.removeReaction(
      postFileId: widget.post.fileId,
      nodeEndpoint: widget.nodeEndpoint,
      userPublicKey: widget.userPublicKey!,
      userMnemonic: widget.userMnemonic!,
      reactionKind: previousKind,
    );
    if (!ok) {
      setState(() {
        _myReaction = previousKind;
        _reactionCount = previousCount;
      });
    } else {
      // Refresh reactions from server to get accurate count
      await _loadReactions();
    }
  }

  IconData _reactionIconFor(String? kind) {
    switch (kind) {
      case 'like':
        return Icons.thumb_up_alt_outlined;
      case 'love':
        return Icons.favorite;
      case 'laugh':
        return Icons.emoji_emotions_outlined;
      case 'wow':
        return Icons.emoji_objects_outlined;
      case 'sad':
        return Icons.sentiment_dissatisfied_outlined;
      case 'angry':
        return Icons.sentiment_very_dissatisfied_outlined;
      default:
        return Icons.favorite_border;
    }
  }

  String _reactionLabel(String kind) {
    switch (kind) {
      case 'like':
        return 'Like';
      case 'love':
        return 'Love';
      case 'laugh':
        return 'Haha';
      case 'wow':
        return 'Wow';
      case 'sad':
        return 'Sad';
      case 'angry':
        return 'Angry';
      default:
        return kind;
    }
  }
}


