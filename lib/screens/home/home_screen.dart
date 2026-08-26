import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/widgets/navigation_menu.dart';
import 'package:deltanium_app/features/local_user/local_user_home_screen.dart';
import 'package:deltanium_app/models/user_profile.dart';

class HomeScreen extends StatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

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
              Navigator.pop(context); // Close drawer on mobile
            }
          },
        ),
      ) : null,
      body: Row(
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
              ),
            ),
          
          // Main content area
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }
} 