import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/widgets/navigation_menu.dart';
import 'package:deltanium_app/features/profile/screens/local_user_profile_screen.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/features/posts/screens/following_posts_screen.dart';
import 'package:deltanium_app/features/posts/screens/public_posts_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/services/chat_service.dart';

class LocalUserHomeScreen extends StatefulWidget {
  final UserProfile userProfile;

  const LocalUserHomeScreen({Key? key, required this.userProfile}) : super(key: key);

  @override
  State<LocalUserHomeScreen> createState() => _LocalUserHomeScreenState();
}

class _LocalUserHomeScreenState extends State<LocalUserHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  int _unreadMessageCount = 0;
  
  final List<Map<String, dynamic>> _privatePosts = [];

  final List<Map<String, String>> _trendingTopics = [
    {
      'topic': '#Blockchain',
      'posts': '1,024 posts',
    },
    {
      'topic': '#Deltanium',
      'posts': '872 posts',
    },
    {
      'topic': '#Web3',
      'posts': '521 posts',
    },
    {
      'topic': '#Crypto',
      'posts': '320 posts',
    },
    {
      'topic': '#Decentralized',
      'posts': '245 posts',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await ChatService.getUnreadCount();
      if (mounted) {
        setState(() => _unreadMessageCount = count);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 1200;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode 
          ? DeltaniumTheme.backgroundDark 
          : DeltaniumTheme.backgroundLight,
      drawer: !isDesktop ? Drawer(
        backgroundColor: isDarkMode 
            ? DeltaniumTheme.black 
            : DeltaniumTheme.white,
        child: NavigationMenu(
          selectedIndex: _selectedIndex,
          onItemSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
            if (!isDesktop) {
              Navigator.pop(context);
            }
            _handleNavigationItemSelected(index);
          },
          handleOwnNavigation: true,
        ),
      ) : null,
      body: Stack(
        children: [
          // Background for sidebar
          Row(
            children: [
              // ĐÃ XOÁ CONTAINER WIDTH 280 ĐỂ TRÁNH VÙNG TRẮNG
              // if (isDesktop) 
              //   Container(
              //     width: 280,
              //     color: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
              //   ),
              Expanded(
                child: Container(
                  color: isDarkMode 
                      ? DeltaniumTheme.backgroundDark 
                      : DeltaniumTheme.backgroundLight,
                ),
              ),
            ],
          ),
          
          // Main content layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Navigation menu for desktop
              // ĐÃ XOÁ PHẦN SIDEBAR NÀY ĐỂ TRÁNH BỊ 2 SIDEBAR
              // if (isDesktop)
              //   Container(
              //     width: 280,
              //     decoration: BoxDecoration(
              //       color: isDarkMode 
              //           ? DeltaniumTheme.black 
              //           : DeltaniumTheme.white,
              //       border: Border(
              //         right: BorderSide(
              //           color: isDarkMode 
              //               ? DeltaniumTheme.darkDividerColor 
              //               : DeltaniumTheme.lightDividerColor,
              //         ),
              //       ),
              //     ),
              //     child: NavigationMenu(
              //       selectedIndex: _selectedIndex,
              //       onItemSelected: (index) {
              //         setState(() {
              //           _selectedIndex = index;
              //         });
              //         _handleNavigationItemSelected(index);
              //       },
              //       handleOwnNavigation: true,
              //     ),
              //   ),
              // Main content area
              Expanded(
                child: Column(
                  children: [
                    // Header with the "D" logo and settings icon
                    Container(
                      color: isDarkMode 
                          ? DeltaniumTheme.black 
                          : DeltaniumTheme.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 24), // For balance
                          Text(
                            'D',
                            style: TextStyle(
                              color: isDarkMode 
                                  ? DeltaniumTheme.primaryTan 
                                  : DeltaniumTheme.primaryBrown,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Message icon with badge
                              Stack(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.mail_outline),
                                    onPressed: () => context.go(AppRoutes.messages),
                                    color: isDarkMode 
                                        ? DeltaniumTheme.darkTextSecondaryColor 
                                        : DeltaniumTheme.lightTextSecondaryColor,
                                    tooltip: 'Messages',
                                  ),
                                  if (_unreadMessageCount > 0)
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 18,
                                          minHeight: 18,
                                        ),
                                        child: Text(
                                          _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings),
                                onPressed: () {},
                                color: isDarkMode 
                                    ? DeltaniumTheme.darkTextSecondaryColor 
                                    : DeltaniumTheme.lightTextSecondaryColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Tab bar
                    Container(
                      color: isDarkMode 
                          ? DeltaniumTheme.black 
                          : DeltaniumTheme.white,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: isDarkMode 
                            ? DeltaniumTheme.primaryTan 
                            : DeltaniumTheme.primaryBrown,
                        unselectedLabelColor: isDarkMode 
                            ? DeltaniumTheme.darkTextSecondaryColor 
                            : DeltaniumTheme.lightTextSecondaryColor,
                        indicatorColor: isDarkMode 
                            ? DeltaniumTheme.primaryTan 
                            : DeltaniumTheme.primaryBrown,
                        tabs: const [
                          Tab(text: 'My Posts'),
                          Tab(text: 'Following'),
                          Tab(text: 'Public'),
                        ],
                      ),
                    ),
                    
                    // Tab content
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: TabBarView(
                            physics: const NeverScrollableScrollPhysics(), // 🔧 FIX: Disable swipe gestures - only allow tab header taps
                            controller: _tabController,
                            children: [
                              // My Posts Tab - Shows user's posts
                              const MyPostsScreen(),
                              
                              // Following Posts Tab - Shows posts shared with followers
                              const FollowingPostsScreen(),
                              
                              // Public Posts Tab - Shows all public posts
                              const PublicPostsScreen(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyTabContent(String tabName, bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dashboard,
            size: 80,
            color: isDarkMode 
                ? DeltaniumTheme.darkTextSecondaryColor 
                : DeltaniumTheme.lightTextSecondaryColor,
          ),
          const SizedBox(height: 24),
          Text(
            '$tabName Tab',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextPrimaryColor 
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This tab is currently empty.',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextSecondaryColor 
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode 
                  ? DeltaniumTheme.primaryTan 
                  : DeltaniumTheme.primaryBrown,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Refresh',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Handle navigation
  void _handleNavigationItemSelected(int index) {
    switch (index) {
      case 0: // Home
        // We're already on home, so do nothing or refresh
        break;
      case 1: // Search
        context.go(AppRoutes.search);
        break;
      case 2: // Profile
        context.go(AppRoutes.localUserProfile, extra: widget.userProfile);
        break;
      case 3: // Messages
        context.go(AppRoutes.messages);
        break;
    }
  }
} 