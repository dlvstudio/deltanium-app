import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/posts/screens/following_posts_screen.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/features/posts/screens/public_posts_screen.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/services/chat_service.dart';
import 'package:deltanium_app/widgets/navigation_menu.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class LocalUserHomeScreen extends StatefulWidget {
  final UserProfile userProfile;

  const LocalUserHomeScreen({Key? key, required this.userProfile}) : super(key: key);

  @override
  State<LocalUserHomeScreen> createState() => _LocalUserHomeScreenState();
}

class _LocalUserHomeScreenState extends State<LocalUserHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  int _unreadMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await ChatService.getUnreadCount();
      if (mounted) setState(() => _unreadMessageCount = count);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLangBuilder(builder: _build);

  Widget _build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 980;
    final showRightRail = screenWidth >= 1200;

    return Scaffold(
      backgroundColor: Brand.ink,
      drawer: !isDesktop
          ? Drawer(
              backgroundColor: Brand.ink,
              child: NavigationMenu(
                selectedIndex: _selectedIndex,
                onItemSelected: (index) {
                  setState(() => _selectedIndex = index);
                  Navigator.pop(context);
                  _handleNavigationItemSelected(index);
                },
                handleOwnNavigation: true,
              ),
            )
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop)
            SizedBox(
              width: 248,
              child: NavigationMenu(
                selectedIndex: _selectedIndex,
                onItemSelected: (index) {
                  setState(() => _selectedIndex = index);
                  _handleNavigationItemSelected(index);
                },
                handleOwnNavigation: true,
              ),
            ),
          if (isDesktop)
            const VerticalDivider(width: 1, thickness: 1, color: DeltaniumTheme.dividerDark),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(isDesktop),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: DeltaniumTheme.dividerDark),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Brand.sand,
                    unselectedLabelColor: Brand.muted,
                    indicatorColor: Brand.sand,
                    indicatorWeight: 2.5,
                    dividerColor: Colors.transparent,
                    labelStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    unselectedLabelStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    tabs: [
                      Tab(text: tr('home.tab.mine')),
                      Tab(text: tr('home.tab.following')),
                      Tab(text: tr('home.tab.public')),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: Brand.inkSoft,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: TabBarView(
                                physics: const NeverScrollableScrollPhysics(),
                                controller: _tabController,
                                children: const [
                                  MyPostsScreen(),
                                  FollowingPostsScreen(),
                                  PublicPostsScreen(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (showRightRail) ...[
                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: DeltaniumTheme.dividerDark,
                        ),
                        SizedBox(
                          width: 300,
                          child: _buildRightRail(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDesktop) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Brand.ink,
        border: Border(
          bottom: BorderSide(color: DeltaniumTheme.dividerDark),
        ),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Brand.text),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          if (!isDesktop)
            Text(
              'Deltanium',
              style: GoogleFonts.syne(
                color: Brand.text,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          const Spacer(),
          const LangSwitch(color: Brand.muted, activeColor: Brand.sand),
          IconButton(
            tooltip: tr('nav.messages'),
            onPressed: () => context.go(AppRoutes.messages),
            icon: Badge(
              isLabelVisible: _unreadMessageCount > 0,
              label: Text(
                _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount',
                style: const TextStyle(fontSize: 10, color: Brand.ink),
              ),
              backgroundColor: Brand.sand,
              child: const Icon(Icons.mail_outline_rounded, color: Brand.muted),
            ),
          ),
          IconButton(
            tooltip: tr('nav.profile'),
            onPressed: () => context.go(
              AppRoutes.localUserProfile,
              extra: widget.userProfile,
            ),
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: Brand.sand.withValues(alpha: 0.18),
              child: Text(
                _initial,
                style: GoogleFonts.syne(
                  color: Brand.sand,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _displayName {
    final full = widget.userProfile.fullName?.trim();
    if (full != null && full.isNotEmpty) return full;
    final email = widget.userProfile.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'You';
  }

  String get _initial => _displayName[0].toUpperCase();

  Widget _buildRightRail() {
    final name = _displayName;
    final key = widget.userProfile.publicKey;
    final shortKey = key.length > 16
        ? '${key.substring(0, 8)}…${key.substring(key.length - 6)}'
        : key;

    return ColoredBox(
      color: Brand.ink,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your space',
            style: GoogleFonts.syne(
              color: Brand.text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Brand.panel,
              borderRadius: BorderRadius.circular(Brand.radius + 4),
              border: Border.all(color: Brand.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Brand.sand.withValues(alpha: 0.18),
                      child: Text(
                        name[0].toUpperCase(),
                        style: GoogleFonts.syne(
                          color: Brand.sand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.manrope(
                              color: Brand.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            shortKey,
                            style: GoogleFonts.manrope(
                              color: Brand.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => context.go(
                    AppRoutes.localUserProfile,
                    extra: widget.userProfile,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Brand.text,
                    side: const BorderSide(color: Brand.line),
                    minimumSize: const Size.fromHeight(40),
                  ),
                  child: const Text('View profile'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Tips',
            style: GoogleFonts.syne(
              color: Brand.text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          _tipCard(
            'Encrypted by default',
            'Share posts with followers privately, or publish to the public feed.',
          ),
          const SizedBox(height: 10),
          _tipCard(
            'Message anyone',
            'Paste a compressed public key to start an encrypted chat.',
          ),
        ],
      ),
    );
  }

  Widget _tipCard(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.panel,
        borderRadius: BorderRadius.circular(Brand.radius + 2),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.manrope(
              color: Brand.sand,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.manrope(
              color: Brand.muted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  void _handleNavigationItemSelected(int index) {
    switch (index) {
      case 0:
        break;
      case 1:
        context.go(AppRoutes.search);
        break;
      case 2:
        context.go(AppRoutes.localUserProfile, extra: widget.userProfile);
        break;
      case 3:
        context.go(AppRoutes.messages);
        break;
      case 4:
        context.go(AppRoutes.transactions);
        break;
    }
  }
}
