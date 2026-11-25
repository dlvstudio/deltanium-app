import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/messages/screens/chat_conversation_screen.dart';
import 'package:deltanium_app/models/user_discovery.dart';
import 'package:deltanium_app/services/chat_service.dart';
import 'package:deltanium_app/services/user_discovery_service.dart';
import 'package:deltanium_app/widgets/creator_support.dart';
import 'package:deltanium_app/widgets/navigation_menu.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class SearchScreen extends StatefulWidget {
  /// Opens with this search already run (a post author's public key, from the feed).
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final UserDiscoveryService _userDiscoveryService = UserDiscoveryService();
  
  late TabController _tabController;
  int _selectedIndex = 1; // Search is index 1 in NavigationMenu
  
  List<DiscoveredUser> _searchResults = [];
  List<DiscoveredUser> _recentUsers = [];
  List<DiscoveredUser> _followingUsers = [];
  
  bool _isSearching = false;
  bool _isLoadingRecent = true;
  bool _isLoadingFollowing = true;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRecentUsers();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _searchController.text = q;
      _searchUsers(q);
    }
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }
  
  void _handleNavigationItemSelected(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        context.go(AppRoutes.localUserHome);
        break;
      case 1:
        break;
      case 2:
        context.go(AppRoutes.localUserProfile);
        break;
      case 3:
        context.go(AppRoutes.messages);
        break;
      case 4:
        context.go(AppRoutes.transactions);
        break;
    }
  }
  
  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });
    
    try {
      final results = await _userDiscoveryService.searchUsers(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Search failed: ${e.toString()}';
        _isSearching = false;
      });
    }
  }
  
  Future<void> _loadRecentUsers() async {
    setState(() {
      _isLoadingRecent = true;
      _errorMessage = null;
    });
    
    try {
      final users = await _userDiscoveryService.getRecentUsers();
      setState(() {
        _recentUsers = users;
        _isLoadingRecent = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load recent users: ${e.toString()}';
        _isLoadingRecent = false;
      });
    }
  }
  
  Future<void> _loadFollowingUsers() async {
    setState(() {
      _isLoadingFollowing = true;
      _errorMessage = null;
    });
    
    try {
      final users = await _userDiscoveryService.getFollowingUsers();
      setState(() {
        _followingUsers = users;
        _isLoadingFollowing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load following users: ${e.toString()}';
        _isLoadingFollowing = false;
      });
    }
  }
  
  Future<void> _toggleFollowUser(DiscoveredUser user) async {
    try {
      bool success;
      if (user.isFollowing) {
        success = await _userDiscoveryService.unfollowUser(user.publicKey);
      } else {
        success = await _userDiscoveryService.followUser(user.publicKey);
      }
      
      if (success) {
        setState(() {
          // Update user in search results
          final searchIndex = _searchResults.indexWhere((u) => u.publicKey == user.publicKey);
          if (searchIndex != -1) {
            _searchResults[searchIndex] = _withFollow(_searchResults[searchIndex], !user.isFollowing);
          }
          
          // Update user in recent users
          final recentIndex = _recentUsers.indexWhere((u) => u.publicKey == user.publicKey);
          if (recentIndex != -1) {
            _recentUsers[recentIndex] = _withFollow(_recentUsers[recentIndex], !user.isFollowing);
          }
          
          // Update following list
          if (user.isFollowing) {
            // Remove from following list
            _followingUsers.removeWhere((u) => u.publicKey == user.publicKey);
          } else {
            // Add to following list
            final updatedUser = _withFollow(user, true);
            _followingUsers.insert(0, updatedUser);
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(user.isFollowing ? 'Unfollowed ${user.displayName ?? 'user'}' : 'Following ${user.displayName ?? 'user'}'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update follow status'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 980;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.ink,
      drawer: !isDesktop
          ? Drawer(
              backgroundColor: Brand.ink,
              child: NavigationMenu(
                selectedIndex: _selectedIndex,
                onItemSelected: (index) {
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
                onItemSelected: _handleNavigationItemSelected,
                handleOwnNavigation: true,
              ),
            ),
          if (isDesktop)
            const VerticalDivider(width: 1, thickness: 1, color: DeltaniumTheme.dividerDark),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
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
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.manrope(color: Brand.text),
                          decoration: InputDecoration(
                            hintText: 'Search users…',
                            hintStyle: GoogleFonts.manrope(color: Brand.muted),
                            prefixIcon: const Icon(Icons.search_rounded, color: Brand.sand, size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Brand.muted, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchUsers('');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Brand.inkSoft,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Brand.radius + 10),
                              borderSide: const BorderSide(color: Brand.line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Brand.radius + 10),
                              borderSide: const BorderSide(color: Brand.line),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Brand.radius + 10),
                              borderSide: const BorderSide(color: Brand.sand, width: 1.4),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {});
                            if (value.trim().isNotEmpty) {
                              _searchUsers(value);
                            } else {
                              setState(() {
                                _searchResults = [];
                                _isSearching = false;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_searchController.text.isEmpty)
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
                      dividerColor: Colors.transparent,
                      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                      unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w500),
                      tabs: const [
                        Tab(text: 'Recent Users'),
                        Tab(text: 'Discover'),
                      ],
                    ),
                  ),
                Expanded(
                  child: ColoredBox(
                    color: Brand.inkSoft,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: _searchController.text.isNotEmpty
                            ? _buildSearchResults(isDarkMode)
                            : TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildRecentUsers(isDarkMode),
                                  _buildDiscoverSection(isDarkMode),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(bool isDarkMode) {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextSecondaryColor 
                    : DeltaniumTheme.lightTextSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextSecondaryColor 
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextPrimaryColor 
                    : DeltaniumTheme.lightTextPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with a different term',
              style: TextStyle(
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextSecondaryColor 
                    : DeltaniumTheme.lightTextSecondaryColor,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildUserCard(_searchResults[index], isDarkMode);
      },
    );
  }
  
  Widget _buildRecentUsers(bool isDarkMode) {
    if (_isLoadingRecent) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_recentUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextSecondaryColor 
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No recent users',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextPrimaryColor 
                    : DeltaniumTheme.lightTextPrimaryColor,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRecentUsers,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadRecentUsers,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _recentUsers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'New users who recently joined Deltanium',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode 
                      ? DeltaniumTheme.darkTextSecondaryColor 
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
            );
          }
          return _buildUserCard(_recentUsers[index - 1], isDarkMode);
        },
      ),
    );
  }
  
  Widget _buildFollowingUsers(bool isDarkMode) {
    if (_isLoadingFollowing) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_followingUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_outlined,
              size: 64,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextSecondaryColor 
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Not following anyone yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextPrimaryColor 
                    : DeltaniumTheme.lightTextPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Discover and follow interesting users',
              style: TextStyle(
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextSecondaryColor 
                    : DeltaniumTheme.lightTextSecondaryColor,
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadFollowingUsers,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _followingUsers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Users you are following',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode 
                      ? DeltaniumTheme.darkTextSecondaryColor 
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
            );
          }
          return _buildUserCard(_followingUsers[index - 1], isDarkMode);
        },
      ),
    );
  }
  
  Widget _buildDiscoverSection(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.explore_outlined,
            size: 64,
            color: isDarkMode 
                ? DeltaniumTheme.primaryTan 
                : DeltaniumTheme.primaryBrown,
          ),
          const SizedBox(height: 16),
          Text(
            'Discover Features',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextPrimaryColor 
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon! Find trending topics, suggested users, and more.',
            style: TextStyle(
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextSecondaryColor 
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Future<void> _startChatWithUser(DiscoveredUser user) async {
    try {
      final conv = await ChatService.createOrGetConversation(
        recipientPubKey: user.publicKey,
      );
      if (conv != null && mounted) {
        final convId = conv['conversationId'] ?? conv['ConversationId'] ?? '';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatConversationScreen(
              conversationId: convId,
              otherPubKey: user.publicKey,
              otherName: user.displayName ?? user.shortPublicKey,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start chat: $e')),
        );
      }
    }
  }

  Widget _buildUserCard(DiscoveredUser user, bool isDarkMode) {
    final initial = user.displayName?.isNotEmpty == true
        ? user.displayName![0].toUpperCase()
        : user.shortPublicKey.substring(0, 2).toUpperCase();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.panel,
        borderRadius: BorderRadius.circular(Brand.radius + 6),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Brand.sand.withValues(alpha: 0.18),
            backgroundImage:
                user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
            child: user.avatarUrl == null
                ? Text(
                    initial,
                    style: GoogleFonts.syne(
                      color: Brand.sand,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? user.shortPublicKey,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Brand.text,
                  ),
                ),
                Text(
                  user.shortPublicKey,
                  style: GoogleFonts.manrope(fontSize: 12, color: Brand.muted),
                ),
                if (user.bio != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    user.bio!,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.4,
                      color: Brand.text,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                // Wrap, not Row: on narrow cards the chips used to overflow under the action icons.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildStatChip('${user.followersCount}', 'followers'),
                    _buildStatChip('${user.followingCount}', 'following'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${user.formattedJoinDate} · ${user.lastActiveFormatted}',
                  style: GoogleFonts.manrope(fontSize: 12, color: Brand.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.mail_outline_rounded, color: Brand.sand, size: 20),
                onPressed: () => _startChatWithUser(user),
                tooltip: 'Send message',
              ),
              IconButton(
                icon: const Icon(Icons.volunteer_activism_outlined, color: Brand.sand, size: 20),
                onPressed: () => CreatorSupport.showTipDialog(context,
                    toPublicKey: user.publicKey, name: user.displayName ?? user.shortPublicKey),
                tooltip: 'Tip',
              ),
              IconButton(
                icon: const Icon(Icons.workspace_premium_outlined, color: Brand.sand, size: 20),
                onPressed: () => CreatorSupport.showSubscribeDialog(context,
                    creatorPublicKey: user.publicKey, name: user.displayName ?? user.shortPublicKey),
                tooltip: 'Subscribe',
              ),
              OutlinedButton(
                onPressed: () => _toggleFollowUser(user),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: user.isFollowing
                        ? Brand.danger.withValues(alpha: 0.5)
                        : Brand.line,
                  ),
                  foregroundColor: user.isFollowing ? Brand.danger : Brand.sand,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 34),
                ),
                child: Text(
                  user.isFollowing ? 'Unfollow' : 'Follow',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Follow state plus the follower count shown on the card, so it changes right away.
  DiscoveredUser _withFollow(DiscoveredUser u, bool following) {
    if (u.isFollowing == following) return u;
    final count = u.followersCount + (following ? 1 : -1);
    return u.copyWith(isFollowing: following, followersCount: count < 0 ? 0 : count);
  }

  Widget _buildStatChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Brand.inkSoft,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: Brand.line),
      ),
      child: Text(
        '$value $label',
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Brand.muted,
        ),
      ),
    );
  }
} 