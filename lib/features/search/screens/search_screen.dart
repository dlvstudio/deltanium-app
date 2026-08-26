import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/models/user_discovery.dart';
import 'package:deltanium_app/services/user_discovery_service.dart';
import 'package:deltanium_app/services/chat_service.dart';
import 'package:deltanium_app/widgets/navigation_menu.dart';
import 'package:deltanium_app/features/messages/screens/chat_conversation_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/app/router.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

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
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }
  
  void _handleNavigationItemSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
    
    // Handle navigation based on index
    switch (index) {
      case 0: // Home
        context.go(AppRoutes.localUserHome);
        break;
      case 1: // Search (current page, do nothing)
        break;
      case 2: // Profile
        context.go(AppRoutes.localUserProfile);
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
            _searchResults[searchIndex] = _searchResults[searchIndex].copyWith(
              isFollowing: !user.isFollowing,
            );
          }
          
          // Update user in recent users
          final recentIndex = _recentUsers.indexWhere((u) => u.publicKey == user.publicKey);
          if (recentIndex != -1) {
            _recentUsers[recentIndex] = _recentUsers[recentIndex].copyWith(
              isFollowing: !user.isFollowing,
            );
          }
          
          // Update following list
          if (user.isFollowing) {
            // Remove from following list
            _followingUsers.removeWhere((u) => u.publicKey == user.publicKey);
          } else {
            // Add to following list
            final updatedUser = user.copyWith(isFollowing: true);
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
          },
          handleOwnNavigation: false,
        ),
      ) : null,
      body: Stack(
        children: [
          // Background for sidebar
          Row(
            children: [
              if (isDesktop) 
                Container(
                  width: 280,
                  color: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
                ),
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
              if (isDesktop)
                Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: isDarkMode 
                        ? DeltaniumTheme.black 
                        : DeltaniumTheme.white,
                    border: Border(
                      right: BorderSide(
                        color: isDarkMode 
                            ? DeltaniumTheme.darkDividerColor 
                            : DeltaniumTheme.lightDividerColor,
                      ),
                    ),
                  ),
                  child: NavigationMenu(
                    selectedIndex: _selectedIndex,
                    onItemSelected: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    handleOwnNavigation: false,
                  ),
                ),
              
              // Main content area
              Expanded(
                child: Column(
                  children: [
                    // Header with search bar
                    Container(
                      color: isDarkMode 
                          ? DeltaniumTheme.black 
                          : DeltaniumTheme.white,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Menu button for mobile
                          if (!isDesktop)
                            Builder(
                              builder: (context) => IconButton(
                                icon: Icon(
                                  Icons.menu,
                                  color: isDarkMode 
                                      ? DeltaniumTheme.primaryTan 
                                      : DeltaniumTheme.primaryBrown,
                                ),
                                onPressed: () => Scaffold.of(context).openDrawer(),
                              ),
                            ),
                          
                          // Search field
                          Expanded(
                            child: Container(
                              height: 40,
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search users...',
                                  hintStyle: TextStyle(
                                    color: isDarkMode 
                                        ? DeltaniumTheme.darkTextSecondaryColor 
                                        : DeltaniumTheme.lightTextSecondaryColor,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: isDarkMode 
                                        ? DeltaniumTheme.primaryTan 
                                        : DeltaniumTheme.primaryBrown,
                                    size: 20,
                                  ),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(
                                            Icons.clear,
                                            color: isDarkMode 
                                                ? DeltaniumTheme.darkTextSecondaryColor 
                                                : DeltaniumTheme.lightTextSecondaryColor,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            _searchUsers('');
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: isDarkMode 
                                      ? DeltaniumTheme.backgroundDark 
                                      : DeltaniumTheme.backgroundLight,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                      color: isDarkMode 
                                          ? DeltaniumTheme.darkDividerColor 
                                          : DeltaniumTheme.lightDividerColor,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                      color: isDarkMode 
                                          ? DeltaniumTheme.primaryTan 
                                          : DeltaniumTheme.primaryBrown,
                                      width: 2,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                      color: isDarkMode 
                                          ? DeltaniumTheme.darkDividerColor 
                                          : DeltaniumTheme.lightDividerColor,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                                style: TextStyle(
                                  color: isDarkMode 
                                      ? DeltaniumTheme.darkTextPrimaryColor 
                                      : DeltaniumTheme.lightTextPrimaryColor,
                                ),
                                onChanged: (value) {
                                  setState(() {}); // Rebuild to show/hide clear button
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
                          ),
                        ],
                      ),
                    ),
                    
                    // Tab bar (only show when not searching) - remove Following Posts
                    if (_searchController.text.isEmpty)
                      Container(
                        color: isDarkMode 
                            ? DeltaniumTheme.black 
                            : DeltaniumTheme.white,
                        child: TabBar(
                          controller: _tabController,
                          indicatorColor: isDarkMode 
                              ? DeltaniumTheme.primaryTan 
                              : DeltaniumTheme.primaryBrown,
                          labelColor: isDarkMode 
                              ? DeltaniumTheme.primaryTan 
                              : DeltaniumTheme.primaryBrown,
                          unselectedLabelColor: isDarkMode 
                              ? DeltaniumTheme.darkTextSecondaryColor 
                              : DeltaniumTheme.lightTextSecondaryColor,
                          tabs: const [
                            Tab(text: 'Recent Users'),
                            Tab(text: 'Discover'),
                          ],
                        ),
                      ),
                    
                    // Main content
                    Expanded(
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
                  ],
                ),
              ),
            ],
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: isDarkMode 
                  ? DeltaniumTheme.primaryTan 
                  : DeltaniumTheme.primaryBrown,
              backgroundImage: user.avatarUrl != null 
                  ? NetworkImage(user.avatarUrl!) 
                  : null,
              child: user.avatarUrl == null
                  ? Text(
                      user.displayName?.isNotEmpty == true 
                          ? user.displayName![0].toUpperCase()
                          : user.shortPublicKey.substring(0, 2).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display name
                  Text(
                    user.displayName ?? user.shortPublicKey,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode 
                          ? DeltaniumTheme.darkTextPrimaryColor 
                          : DeltaniumTheme.lightTextPrimaryColor,
                    ),
                  ),
                  
                  // Public key (shortened)
                  Text(
                    user.shortPublicKey,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: isDarkMode 
                          ? DeltaniumTheme.darkTextSecondaryColor 
                          : DeltaniumTheme.lightTextSecondaryColor,
                    ),
                  ),
                  
                  // Bio
                  if (user.bio != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      user.bio!,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode 
                            ? DeltaniumTheme.darkTextPrimaryColor 
                            : DeltaniumTheme.lightTextPrimaryColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  
                  const SizedBox(height: 8),
                  
                  // Stats row (hide posts)
                  Row(
                    children: [
                      _buildStatChip('${user.followersCount}', 'followers', isDarkMode),
                      const SizedBox(width: 8),
                      _buildStatChip('${user.followingCount}', 'following', isDarkMode),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Join date and last active
                  Row(
                    children: [
                      Text(
                        user.formattedJoinDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode 
                              ? DeltaniumTheme.darkTextSecondaryColor 
                              : DeltaniumTheme.lightTextSecondaryColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        user.lastActiveFormatted,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode 
                              ? DeltaniumTheme.darkTextSecondaryColor 
                              : DeltaniumTheme.lightTextSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Action buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Message button
                IconButton(
                  icon: Icon(
                    Icons.mail_outline,
                    color: isDarkMode 
                        ? DeltaniumTheme.primaryTan 
                        : DeltaniumTheme.primaryBrown,
                    size: 20,
                  ),
                  onPressed: () => _startChatWithUser(user),
                  tooltip: 'Send message',
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                // Follow button
                OutlinedButton(
                  onPressed: () => _toggleFollowUser(user),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: user.isFollowing
                          ? Colors.red
                          : (isDarkMode 
                              ? DeltaniumTheme.primaryTan 
                              : DeltaniumTheme.primaryBrown),
                    ),
                    foregroundColor: user.isFollowing
                        ? Colors.red
                        : (isDarkMode 
                            ? DeltaniumTheme.primaryTan 
                            : DeltaniumTheme.primaryBrown),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    user.isFollowing ? 'Unfollow' : 'Follow',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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
  
  Widget _buildStatChip(String value, String label, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? DeltaniumTheme.surfaceDark.withOpacity(0.5)
            : DeltaniumTheme.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextPrimaryColor 
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextSecondaryColor 
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }
} 