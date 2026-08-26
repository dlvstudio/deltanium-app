import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/services/chat_service.dart';

class NavigationMenu extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final bool handleOwnNavigation;

  const NavigationMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.handleOwnNavigation = false,
  });

  @override
  State<NavigationMenu> createState() => _NavigationMenuState();
}

class _NavigationMenuState extends State<NavigationMenu> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await ChatService.getUnreadCount();
      if (mounted) {
        setState(() => _unreadCount = count);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _buildMenuItem(
          context,
          icon: Icons.home,
          label: 'Home',
          index: 0,
          route: AppRoutes.localUserHome,
        ),
        _buildMenuItem(
          context,
          icon: Icons.search,
          label: 'Explore',
          index: 1,
          route: AppRoutes.search,
        ),
        _buildMenuItem(
          context,
          icon: Icons.mail_outline,
          label: 'Messages',
          index: 3,
          route: AppRoutes.messages,
          badgeCount: _unreadCount,
        ),
        _buildMenuItem(
          context,
          icon: Icons.person,
          label: 'Profile',
          index: 2,
          route: AppRoutes.localUserProfile,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton(
            onPressed: () {
              // Get user profile from the app state or context
              final userProfile = GoRouterState.of(context).extra;
              if (userProfile is UserProfile) {
                context.go(AppRoutes.createPost, extra: userProfile);
              } else {
                context.go(AppRoutes.createPost);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode 
                  ? DeltaniumTheme.primaryTan 
                  : DeltaniumTheme.primaryBrown,
              foregroundColor: DeltaniumTheme.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              'Create Post',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
    required String route,
    int badgeCount = 0,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isSelected = index == widget.selectedIndex;

    final iconColor = isSelected
        ? isDarkMode
            ? DeltaniumTheme.primaryTan
            : DeltaniumTheme.primaryBrown
        : isDarkMode
            ? DeltaniumTheme.darkTextSecondaryColor
            : DeltaniumTheme.lightTextSecondaryColor;

    Widget leadingWidget = Icon(icon, color: iconColor, size: 24);
    if (badgeCount > 0) {
      leadingWidget = Badge(
        label: Text(
          badgeCount > 99 ? '99+' : '$badgeCount',
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        backgroundColor: Colors.red,
        child: Icon(icon, color: iconColor, size: 24),
      );
    }

    return ListTile(
      leading: leadingWidget,
      title: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? isDarkMode
                  ? DeltaniumTheme.primaryTan
                  : DeltaniumTheme.primaryBrown
              : isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
        ),
      ),
      onTap: () {
        widget.onItemSelected(index);
        
        // Allow parent widget to handle navigation if requested
        if (widget.handleOwnNavigation) {
          return;
        }
        
        // Otherwise handle navigation directly with GoRouter
        if (route.isNotEmpty) {
          context.go(route);
        }
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      selected: isSelected,
      selectedTileColor: isDarkMode
          ? DeltaniumTheme.primaryTan.withOpacity(0.1)
          : DeltaniumTheme.primaryBrown.withOpacity(0.05),
      hoverColor: isDarkMode
          ? DeltaniumTheme.primaryTan.withOpacity(0.05)
          : DeltaniumTheme.primaryBrown.withOpacity(0.03),
    );
  }
} 