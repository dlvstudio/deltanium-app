import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';

class LocalUserProfileScreen extends StatefulWidget {
  final UserProfile userProfile;
  
  const LocalUserProfileScreen({
    super.key,
    required this.userProfile,
  });

  @override
  State<LocalUserProfileScreen> createState() => _LocalUserProfileScreenState();
}

class _LocalUserProfileScreenState extends State<LocalUserProfileScreen> {
  final _authService = AuthService();
  
  // Get compressed public key (always use compressed format)
  String _getCompressedPublicKey(String uncompressedKey) {
    return CryptoService.convertToCompressedPublicKey(uncompressedKey);
  }
  
  // Copy public key to clipboard (always compressed)
  Future<void> _copyPublicKey(BuildContext context) async {
    final keyToCopy = _getCompressedPublicKey(widget.userProfile.publicKey);
    
    await Clipboard.setData(ClipboardData(text: keyToCopy));
    
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Public Key Copied!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Share this with others to receive files',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
  
  // Handle logout process
  Future<void> _handleLogout() async {
    try {
      // Show logout options dialog
      final logoutChoice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Logout Options'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose logout type:'),
              SizedBox(height: 12),
              Text('• Logout: Switch accounts (keep saved credentials)'),
              Text('• Complete Logout: Remove all data (delete all saved accounts)'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('normal'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Logout'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('complete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Complete Logout'),
            ),
          ],
        ),
      );

      if (logoutChoice == null || !mounted) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Perform logout using AuthService
      final success = logoutChoice == 'complete' 
          ? await _authService.completeLogout()
          : await _authService.logout();
      
      if (!mounted) return;
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      if (success) {
        // Show success message
        final message = logoutChoice == 'complete'
            ? 'Completely logged out - all data cleared'
            : 'Logged out successfully';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Navigate to login screen
        context.go(AppRoutes.login);
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Failed to logout. Please try again.'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      // Close loading dialog if still showing
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Error during logout: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? DeltaniumTheme.backgroundDark : DeltaniumTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.localUserHome, extra: widget.userProfile),
        ),
        backgroundColor: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
        iconTheme: IconThemeData(
          color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Content with integrated header
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Header background
                Container(
                  height: 80, // Reduced height
                  width: double.infinity,
                  color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                ),
                
                // Profile Information with top margin to create space for avatar
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Profile Picture - using Transform instead of negative margin
                            Transform.translate(
                              offset: const Offset(0, -30),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isDarkMode
                                        ? DeltaniumTheme.black
                                        : DeltaniumTheme.white,
                                    width: 4,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundImage: widget.userProfile.avatarUrl != null
                                      ? NetworkImage(widget.userProfile.avatarUrl!)
                                      : null,
                                  backgroundColor: isDarkMode
                                      ? DeltaniumTheme.surfaceDark
                                      : DeltaniumTheme.surfaceLight,
                                  child: widget.userProfile.avatarUrl == null
                                      ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                      : null,
                                ),
                              ),
                            ),
                            
                            // Edit Profile Button
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: isDarkMode
                                    ? DeltaniumTheme.primaryTan
                                    : DeltaniumTheme.primaryBrown,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  side: BorderSide(
                                    color: isDarkMode
                                        ? DeltaniumTheme.primaryTan
                                        : DeltaniumTheme.primaryBrown,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              child: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // User Info
                        Text(
                          widget.userProfile.fullName ?? widget.userProfile.email ?? 'Local User',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode 
                              ? DeltaniumTheme.darkTextPrimaryColor 
                              : DeltaniumTheme.lightTextPrimaryColor,
                          ),
                        ),
                        
                        Row(
                          children: [
                            Text(
                              widget.userProfile.email ?? '',
                              style: TextStyle(
                                color: isDarkMode
                                    ? DeltaniumTheme.darkTextSecondaryColor
                                    : DeltaniumTheme.lightTextSecondaryColor,
                              ),
                            ),
                            
                            if (widget.userProfile.isVerified)
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Verified',
                                  style: TextStyle(
                                    color: DeltaniumTheme.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        
                        if (widget.userProfile.bio != null) ...[
                          const SizedBox(height: 12),
                          // Bio
                          Text(
                            widget.userProfile.bio!,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode 
                                ? DeltaniumTheme.darkTextPrimaryColor 
                                : DeltaniumTheme.lightTextPrimaryColor,
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 12),
                        
                        // Public Key display with copy functionality and format toggle
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDarkMode 
                                ? DeltaniumTheme.surfaceDark.withOpacity(0.3)
                                : DeltaniumTheme.surfaceLight.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDarkMode
                                  ? DeltaniumTheme.darkDividerColor
                                  : DeltaniumTheme.lightDividerColor,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.key,
                                    size: 16,
                                    color: isDarkMode
                                        ? DeltaniumTheme.primaryTan
                                        : DeltaniumTheme.primaryBrown,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Public Key',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isDarkMode
                                          ? DeltaniumTheme.darkTextPrimaryColor
                                          : DeltaniumTheme.lightTextPrimaryColor,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () => _copyPublicKey(context),
                                    icon: Icon(
                                      Icons.copy,
                                      size: 18,
                                      color: isDarkMode
                                          ? DeltaniumTheme.primaryTan
                                          : DeltaniumTheme.primaryBrown,
                                    ),
                                    tooltip: 'Copy Public Key',
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Format info
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Compressed (66 chars)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Public key display
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.black.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _getCompressedPublicKey(widget.userProfile.publicKey),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Share this key with others to receive encrypted files. Compressed format saves space.',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: isDarkMode
                                      ? DeltaniumTheme.darkTextSecondaryColor
                                      : DeltaniumTheme.lightTextSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Stats Row removed per new design
                        
                        const SizedBox(height: 24),
                        
                        // Account Information Section
                        Text(
                          'Account Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode 
                              ? DeltaniumTheme.darkTextPrimaryColor 
                              : DeltaniumTheme.lightTextPrimaryColor,
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        _buildInfoItem(
                          Icons.calendar_today,
                          'Joined Date',
                          'January 2023',
                          isDarkMode,
                        ),
                        
                        _buildInfoItem(
                          Icons.badge,
                          'Name',
                          widget.userProfile.fullName ?? '—',
                          isDarkMode,
                        ),
                        _buildInfoItem(
                          Icons.cake,
                          'Birthday',
                          widget.userProfile.dateOfBirth ?? '—',
                          isDarkMode,
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Only keep Logout button
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDarkMode 
                                ? DeltaniumTheme.surfaceDark 
                                : DeltaniumTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _buildActionButton(
                              'Logout',
                              Icons.logout,
                              isDarkMode,
                              () async {
                                await _handleLogout();
                              },
                              isLogout: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoItem(IconData icon, String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDarkMode
                ? DeltaniumTheme.darkTextSecondaryColor
                : DeltaniumTheme.lightTextSecondaryColor,
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isDarkMode
                  ? DeltaniumTheme.darkTextPrimaryColor
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(String label, IconData icon, bool isDarkMode, VoidCallback onPressed, {bool isLogout = false}) {
    final Color textColor = isLogout 
        ? Colors.red 
        : isDarkMode
            ? DeltaniumTheme.primaryTan
            : DeltaniumTheme.primaryBrown;
            
    final Color borderColor = isLogout
        ? Colors.red.withOpacity(0.3)
        : isDarkMode
            ? DeltaniumTheme.surfaceDark
            : DeltaniumTheme.lightDividerColor;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: textColor),
        label: Text(label, style: TextStyle(color: textColor)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDarkMode 
              ? DeltaniumTheme.black 
              : DeltaniumTheme.white,
          foregroundColor: textColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: borderColor,
            ),
          ),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value, bool isDarkMode) {
    return Expanded(
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDarkMode 
                ? DeltaniumTheme.darkTextPrimaryColor 
                : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
} 