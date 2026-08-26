import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final List<Widget>? actions;
  final Widget? leading;

  const CustomAppBar({
    Key? key,
    required this.title,
    this.showBackButton = false,
    this.actions,
    this.leading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return AppBar(
      title: Text(title),
      backgroundColor: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
      elevation: 0,
      centerTitle: true,
      leading: showBackButton
          ? leading ?? IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              ),
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      actions: actions,
      iconTheme: IconThemeData(
        color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
} 