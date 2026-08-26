import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/app/router.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 1024;
    final isTablet = screenWidth > 768 && screenWidth <= 1024;

    return Scaffold(
      backgroundColor: isDarkMode 
          ? DeltaniumTheme.backgroundDark 
          : DeltaniumTheme.backgroundLight,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, isDarkMode, isDesktop),
              _buildHeroSection(context, isDarkMode, isDesktop, isTablet),
              _buildFeaturesSection(isDarkMode, isDesktop),
              _buildArchitectureSection(isDarkMode, isDesktop),
              _buildCallToActionSection(context, isDarkMode, isDesktop),
              _buildFooter(isDarkMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDarkMode, bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 80 : 24,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? DeltaniumTheme.black.withOpacity(0.8)
            : DeltaniumTheme.white.withOpacity(0.9),
        border: Border(
          bottom: BorderSide(
            color: isDarkMode 
                ? DeltaniumTheme.darkDividerColor
                : DeltaniumTheme.lightDividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                      isDarkMode ? DeltaniumTheme.primaryBrown : DeltaniumTheme.primaryTan,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'D',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Deltanium',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode 
                      ? DeltaniumTheme.primaryTan 
                      : DeltaniumTheme.primaryBrown,
                ),
              ),
            ],
          ),
          if (isDesktop) ...[
            Row(
              children: [
                _buildNavButton('Features', () {
                  _scrollToSection(context, 'features');
                }, isDarkMode),
                const SizedBox(width: 24),
                _buildNavButton('Architecture', () {
                  _scrollToSection(context, 'architecture');
                }, isDarkMode),
                const SizedBox(width: 24),
                _buildNavButton('Contact', () {
                  _scrollToSection(context, 'footer');
                }, isDarkMode),
                const SizedBox(width: 32),
                _buildPrimaryButton('Get Started', () {
                  context.go(AppRoutes.login);
                }, isDarkMode),
              ],
            ),
          ] else ...[
            IconButton(
              onPressed: () {
                context.go(AppRoutes.login);
              },
              icon: Icon(
                Icons.login,
                color: isDarkMode 
                    ? DeltaniumTheme.primaryTan 
                    : DeltaniumTheme.primaryBrown,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, bool isDarkMode, bool isDesktop, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 80 : 24,
        vertical: isDesktop ? 120 : 60,
      ),
      child: isDesktop
          ? Row(
              children: [
                // Left: Text
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'The Future of Decentralized Social Media',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          color: isDarkMode
                              ? DeltaniumTheme.darkTextPrimaryColor
                              : DeltaniumTheme.lightTextPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Own your data, enjoy true privacy, and connect without limits. Deltanium combines blockchain security with a modern social experience.',
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.6,
                          color: isDarkMode
                              ? DeltaniumTheme.darkTextSecondaryColor
                              : DeltaniumTheme.lightTextSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 48),
                      Row(
                        children: [
                          _buildPrimaryButton('Start Free', () {
                            context.go(AppRoutes.login);
                          }, isDarkMode, large: true),
                          const SizedBox(width: 24),
                          _buildSecondaryButton('Learn More', () {
                            _scrollToSection(context, 'features');
                          }, isDarkMode, large: true),
                        ],
                      ),
                      const SizedBox(height: 32),
                      _buildTrustIndicators(isDarkMode),
                    ],
                  ),
                ),
                const SizedBox(width: 80),
                // Right: Illustration
                Expanded(
                  flex: 4,
                  child: _buildHeroImage(isDarkMode),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: isTablet ? 300 : 220,
                  height: isTablet ? 300 : 220,
                  child: _buildHeroImage(isDarkMode),
                ),
                const SizedBox(height: 40),
                Text(
                  'The Future of Decentralized Social Media',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isTablet ? 40 : 28,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    color: isDarkMode
                        ? DeltaniumTheme.darkTextPrimaryColor
                        : DeltaniumTheme.lightTextPrimaryColor,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Own your data, enjoy true privacy, and connect without limits. Deltanium combines blockchain security with a modern social experience.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: isDarkMode
                        ? DeltaniumTheme.darkTextSecondaryColor
                        : DeltaniumTheme.lightTextSecondaryColor,
                  ),
                ),
                const SizedBox(height: 32),
                _buildPrimaryButton('Start Free', () {
                  context.go(AppRoutes.login);
                }, isDarkMode, large: true),
                const SizedBox(height: 16),
                _buildSecondaryButton('Learn More', () {
                  _scrollToSection(context, 'features');
                }, isDarkMode, large: true),
                const SizedBox(height: 32),
                _buildTrustIndicators(isDarkMode),
              ],
            ),
    );
  }

  Widget _buildHeroImage(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDarkMode ? DeltaniumTheme.primaryTan.withOpacity(0.2) : DeltaniumTheme.primaryBrown.withOpacity(0.1),
            isDarkMode ? DeltaniumTheme.primaryBrown.withOpacity(0.2) : DeltaniumTheme.primaryTan.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          'images/banner.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildTrustIndicators(bool isDarkMode) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTrustBadge('🔒', 'Encrypted', isDarkMode),
        const SizedBox(width: 24),
        _buildTrustBadge('⛓️', 'Blockchain', isDarkMode),
        const SizedBox(width: 24),
        _buildTrustBadge('🌐', 'Decentralized', isDarkMode),
      ],
    );
  }

  Widget _buildTrustBadge(String emoji, String label, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? DeltaniumTheme.surfaceDark.withOpacity(0.5)
            : DeltaniumTheme.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode
              ? DeltaniumTheme.darkDividerColor
              : DeltaniumTheme.lightDividerColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextPrimaryColor
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection(bool isDarkMode, bool isDesktop) {
    return Container(
      key: const ValueKey('features'),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 80 : 24,
        vertical: isDesktop ? 100 : 60,
      ),
      color: isDarkMode
          ? DeltaniumTheme.surfaceDark.withOpacity(0.3)
          : DeltaniumTheme.surfaceLight.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Key Features',
            style: TextStyle(
              fontSize: isDesktop ? 40 : 28,
              fontWeight: FontWeight.bold,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextPrimaryColor
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 32,
            runSpacing: 32,
            children: [
              _buildFeatureCard(
                icon: Icons.vpn_key,
                title: 'Secure Registration',
                desc: 'Generate mnemonic and public key. No centralized password storage.',
                isDarkMode: isDarkMode,
              ),
              _buildFeatureCard(
                icon: Icons.cloud_upload,
                title: 'Decentralized Storage',
                desc: 'Files, posts, and data are stored across distributed nodes.',
                isDarkMode: isDarkMode,
              ),
              _buildFeatureCard(
                icon: Icons.verified_user,
                title: 'Blockchain Authentication',
                desc: 'All actions are digitally signed and verifiable.',
                isDarkMode: isDarkMode,
              ),
              _buildFeatureCard(
                icon: Icons.lock,
                title: 'True Privacy',
                desc: 'End-to-end encryption. No censorship.',
                isDarkMode: isDarkMode,
              ),
              _buildFeatureCard(
                icon: Icons.devices,
                title: 'Modern UI/UX',
                desc: 'Cross-platform, responsive, dark mode, smooth experience.',
                isDarkMode: isDarkMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({required IconData icon, required String title, required String desc, required bool isDarkMode}) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.black : Colors.grey).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchitectureSection(bool isDarkMode, bool isDesktop) {
    return Container(
      key: const ValueKey('architecture'),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 80 : 24,
        vertical: isDesktop ? 80 : 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'System Architecture',
            style: TextStyle(
              fontSize: isDesktop ? 36 : 24,
              fontWeight: FontWeight.bold,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextPrimaryColor
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Deltanium combines blockchain, decentralized storage, and a modern social network. All actions are digitally signed, data is end-to-end encrypted, and stored across distributed nodes.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
          const SizedBox(height: 40),
          _buildArchitectureDiagram(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildArchitectureDiagram(bool isDarkMode) {
    return Container(
      width: 600,
      constraints: const BoxConstraints(maxWidth: 800),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildArchNode(Icons.person, 'User', isDarkMode),
              Icon(Icons.arrow_forward, color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown),
              _buildArchNode(Icons.vpn_key, 'Mnemonic\nPublic Key', isDarkMode),
              Icon(Icons.arrow_forward, color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown),
              _buildArchNode(Icons.cloud, 'Store Node', isDarkMode),
              Icon(Icons.arrow_forward, color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown),
              _buildArchNode(Icons.verified, 'Blockchain', isDarkMode),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Flow: Register → Generate mnemonic/public key → Login → Post/file → Store node → Blockchain verification',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchNode(IconData icon, String label, bool isDarkMode) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? DeltaniumTheme.primaryTan.withOpacity(0.15) : DeltaniumTheme.primaryBrown.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 32, color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDarkMode
                ? DeltaniumTheme.darkTextPrimaryColor
                : DeltaniumTheme.lightTextPrimaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildCallToActionSection(BuildContext context, bool isDarkMode, bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 80 : 24,
        vertical: isDesktop ? 80 : 40,
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(
            'Ready to join the decentralized social network?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isDesktop ? 32 : 22,
              fontWeight: FontWeight.bold,
              color: isDarkMode
                  ? DeltaniumTheme.primaryTan
                  : DeltaniumTheme.primaryBrown,
            ),
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton('Sign Up / Login Now', () {
            context.go(AppRoutes.login);
          }, isDarkMode, large: true),
          const SizedBox(height: 16),
          _buildSecondaryButton('View Documentation', () {
            // TODO: Link to docs/github
          }, isDarkMode, large: false),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDarkMode) {
    return Container(
      key: const ValueKey('footer'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      color: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Deltanium © 2024 | Decentralized Social Network | MIT License',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Github: github.com/deltanium | Contact: contact@deltanium.org',
            style: TextStyle(
              fontSize: 13,
              color: isDarkMode
                  ? DeltaniumTheme.darkTextSecondaryColor
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onPressed, bool isDarkMode, {bool large = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
        foregroundColor: DeltaniumTheme.white,
        padding: EdgeInsets.symmetric(vertical: large ? 20 : 14, horizontal: large ? 36 : 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        textStyle: TextStyle(fontSize: large ? 18 : 15, fontWeight: FontWeight.bold),
        elevation: 2,
      ),
      child: Text(label),
    );
  }

  Widget _buildSecondaryButton(String label, VoidCallback onPressed, bool isDarkMode, {bool large = false}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
        side: BorderSide(color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown, width: 2),
        padding: EdgeInsets.symmetric(vertical: large ? 20 : 14, horizontal: large ? 36 : 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        textStyle: TextStyle(fontSize: large ? 18 : 15, fontWeight: FontWeight.bold),
      ),
      child: Text(label),
    );
  }

  Widget _buildNavButton(String text, VoidCallback onPressed, bool isDarkMode) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          color: isDarkMode
              ? DeltaniumTheme.darkTextPrimaryColor
              : DeltaniumTheme.lightTextPrimaryColor,
        ),
      ),
    );
  }

  void _scrollToSection(BuildContext context, String sectionKey) {
    // TODO: Implement scroll to section if needed (requires ScrollController)
  }
} 