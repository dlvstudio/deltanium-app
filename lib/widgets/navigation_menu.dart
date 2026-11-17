import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/icons/logo.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Brand.sand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Brand.line),
                  ),
                  child: Text(
                    'D',
                    style: GoogleFonts.syne(
                      color: Brand.sand,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Deltanium',
              style: GoogleFonts.syne(
                color: Brand.text,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      _buildMenuItem(
        context,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: 'Home',
        index: 0,
        route: AppRoutes.localUserHome,
      ),
      _buildMenuItem(
        context,
        icon: Icons.search_rounded,
        selectedIcon: Icons.search_rounded,
        label: 'Explore',
        index: 1,
        route: AppRoutes.search,
      ),
      _buildMenuItem(
        context,
        icon: Icons.mail_outline_rounded,
        selectedIcon: Icons.mail_rounded,
        label: 'Messages',
        index: 3,
        route: AppRoutes.messages,
        badgeCount: _unreadCount,
      ),
      _buildMenuItem(
        context,
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        label: 'Profile',
        index: 2,
        route: AppRoutes.localUserProfile,
      ),
    ];

    final createButton = Padding(
      padding: const EdgeInsets.only(top: 16),
      child: FilledButton(
        onPressed: () {
          final userProfile = GoRouterState.of(context).extra;
          if (userProfile is UserProfile) {
            context.go(AppRoutes.createPost, extra: userProfile);
          } else {
            context.go(AppRoutes.createPost);
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: Brand.sand,
          foregroundColor: Brand.ink,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radius + 4),
          ),
        ),
        child: Text(
          'Create Post',
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return Container(
      color: Brand.ink,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxHeight.isFinite) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...items,
                    const Spacer(),
                    createButton,
                  ],
                );
              }
              return ListView(
                children: [
                  ...items,
                  createButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
    required String route,
    int badgeCount = 0,
  }) {
    final isSelected = index == widget.selectedIndex;
    final color = isSelected ? Brand.sand : Brand.muted;

    Widget leading = Icon(
      isSelected ? selectedIcon : icon,
      color: color,
      size: 24,
    );
    if (badgeCount > 0) {
      leading = Badge(
        label: Text(
          badgeCount > 99 ? '99+' : '$badgeCount',
          style: const TextStyle(fontSize: 10, color: Brand.ink),
        ),
        backgroundColor: Brand.sand,
        child: leading,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? Brand.sand.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(Brand.radius + 2),
        child: InkWell(
          onTap: () {
            widget.onItemSelected(index);
            if (widget.handleOwnNavigation) return;
            if (route.isNotEmpty) context.go(route);
          },
          borderRadius: BorderRadius.circular(Brand.radius + 2),
          hoverColor: Brand.sand.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Brand.text : DeltaniumTheme.darkTextSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
