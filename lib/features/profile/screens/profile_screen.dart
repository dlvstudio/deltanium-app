import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  
  const ProfileScreen({
    super.key,
    this.userId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 150,
              floating: false,
              pinned: true,
              title: const Text('Profile'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                ),
              ),
            ),
            SliverPersistentHeader(
              delegate: _ProfileHeaderDelegate(
                isDarkMode: isDarkMode,
              ),
              pinned: true,
            ),
            SliverPersistentHeader(
              delegate: _ProfileTabBarDelegate(
                tabController: _tabController,
                isDarkMode: isDarkMode,
              ),
              pinned: true,
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            // Posts Tab
            _buildEmptyTabContent('No posts yet'),
            // Replies Tab
            _buildEmptyTabContent('No replies yet'),
            // Media Tab
            _buildEmptyTabContent('No media yet'),
            // Likes Tab
            _buildEmptyTabContent('No likes yet'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyTabContent(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 40,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When you post or reply, it will show up here',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderDelegate extends SliverPersistentHeaderDelegate {
  final bool isDarkMode;
  
  _ProfileHeaderDelegate({required this.isDarkMode});
  
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Profile Picture
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDarkMode
                          ? DeltaniumTheme.surfaceDark
                          : DeltaniumTheme.surfaceLight,
                      width: 4,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const CircleAvatar(
                    radius: 40,
                    backgroundImage: AssetImage('assets/images/avatar_placeholder.png'),
                  ),
                ),
                
                // Edit Profile Button
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: isDarkMode
                        ? DeltaniumTheme.white
                        : DeltaniumTheme.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: BorderSide(
                        color: isDarkMode
                            ? DeltaniumTheme.surfaceDark
                            : DeltaniumTheme.surfaceLight,
                      ),
                    ),
                  ),
                  child: const Text('Edit profile'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // User Info
            const Text(
              'John Doe',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            Row(
              children: [
                Text(
                  '@johndoe',
                  style: TextStyle(
                    color: isDarkMode
                        ? DeltaniumTheme.surfaceDark
                        : DeltaniumTheme.surfaceLight,
                  ),
                ),
                
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
            
            const SizedBox(height: 12),
            
            // Bio
            const Text(
              'Building decentralized social networks with Deltanium blockchain',
              style: TextStyle(
                fontSize: 14,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Join date
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: isDarkMode
                      ? DeltaniumTheme.surfaceDark
                      : DeltaniumTheme.surfaceLight,
                ),
                const SizedBox(width: 4),
                Text(
                  'Joined June 2023',
                  style: TextStyle(
                    color: isDarkMode
                        ? DeltaniumTheme.surfaceDark
                        : DeltaniumTheme.surfaceLight,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Following/Followers
            Row(
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: isDarkMode
                          ? DeltaniumTheme.surfaceDark
                          : DeltaniumTheme.surfaceLight,
                      fontSize: 14,
                    ),
                    children: const [
                      TextSpan(
                        text: '128',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' Following'),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: isDarkMode
                          ? DeltaniumTheme.surfaceDark
                          : DeltaniumTheme.surfaceLight,
                      fontSize: 14,
                    ),
                    children: const [
                      TextSpan(
                        text: '243',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' Followers'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  double get maxExtent => 270;

  @override
  double get minExtent => 270;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}

class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final bool isDarkMode;
  
  _ProfileTabBarDelegate({
    required this.tabController,
    required this.isDarkMode,
  });
  
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
      child: TabBar(
        controller: tabController,
        indicatorColor: Theme.of(context).primaryColor,
        indicatorWeight: 3,
        labelColor: isDarkMode ? DeltaniumTheme.white : DeltaniumTheme.black,
        unselectedLabelColor: isDarkMode
            ? DeltaniumTheme.surfaceDark
            : DeltaniumTheme.surfaceLight,
        tabs: const [
          Tab(text: 'Posts'),
          Tab(text: 'Replies'),
          Tab(text: 'Media'),
          Tab(text: 'Likes'),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 50;

  @override
  double get minExtent => 50;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
} 