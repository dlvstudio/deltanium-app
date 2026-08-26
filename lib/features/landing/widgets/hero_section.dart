import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/app/router.dart';

class HeroSection extends StatelessWidget {
  final bool isDarkMode;
  final bool isDesktop;
  final bool isTablet;
  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;

  const HeroSection({
    super.key,
    required this.isDarkMode,
    required this.isDesktop,
    required this.isTablet,
    required this.fadeAnimation,
    required this.slideAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: fadeAnimation,
      builder: (context, child) {
        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(
            position: slideAnimation,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 80 : 24,
                vertical: isDesktop ? 120 : 80,
              ),
              child: isDesktop 
                  ? _buildDesktopHero(context)
                  : _buildMobileHero(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopHero(BuildContext context) {
    return Row(
      children: [
        // Left side - Text content
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                    isDarkMode ? DeltaniumTheme.primaryBrown : DeltaniumTheme.primaryTan,
                  ],
                ).createShader(bounds),
                child: Text(
                  'The Future of\nDecentralized\nSocial Media',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Own your content, control your privacy, and connect without limits. Deltanium combines blockchain security with social networking freedom.',
                style: TextStyle(
                  fontSize: 20,
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
                  }, context, large: true),
                  const SizedBox(width: 24),
                  _buildSecondaryButton('Learn More', () {
                    // Scroll to features section
                  }, context, large: true),
                ],
              ),
              const SizedBox(height: 32),
              _buildTrustIndicators(),
            ],
          ),
        ),
        
        const SizedBox(width: 80),
        
        // Right side - Illustration/App preview
        Expanded(
          flex: 4,
          child: _buildHeroImage(),
        ),
      ],
    );
  }

  Widget _buildMobileHero(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Hero image on top for mobile
        Container(
          width: isTablet ? 300 : 250,
          height: isTablet ? 300 : 250,
          child: _buildHeroImage(),
        ),
        
        const SizedBox(height: 48),
        
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              isDarkMode ? DeltaniumTheme.primaryBrown : DeltaniumTheme.primaryTan,
            ],
          ).createShader(bounds),
          child: Text(
            'The Future of\nDecentralized\nSocial Media',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 48 : 36,
              fontWeight: FontWeight.bold,
              height: 1.2,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Own your content, control your privacy, and connect without limits. Deltanium combines blockchain security with social networking freedom.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            height: 1.6,
            color: isDarkMode 
                ? DeltaniumTheme.darkTextSecondaryColor 
                : DeltaniumTheme.lightTextSecondaryColor,
          ),
        ),
        const SizedBox(height: 40),
        Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: _buildPrimaryButton('Start Free', () {
                context.go(AppRoutes.login);
              }, context, large: true),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _buildSecondaryButton('Learn More', () {}, context, large: true),
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildTrustIndicators(),
      ],
    );
  }

  Widget _buildHeroImage() {
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
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.black : Colors.grey).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                    isDarkMode ? DeltaniumTheme.primaryBrown : DeltaniumTheme.primaryTan,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown).withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.security,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Secure & Private',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextPrimaryColor 
                    : DeltaniumTheme.lightTextPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Zero-Knowledge Privacy',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode 
                    ? DeltaniumTheme.darkTextSecondaryColor 
                    : DeltaniumTheme.lightTextSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustIndicators() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildTrustBadge('🔒', 'Encrypted'),
        _buildTrustBadge('⛓️', 'Blockchain'),
        _buildTrustBadge('🌐', 'Decentralized'),
        _buildTrustBadge('🚀', 'Fast'),
      ],
    );
  }

  Widget _buildTrustBadge(String emoji, String label) {
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

  Widget _buildPrimaryButton(String text, VoidCallback onPressed, BuildContext context, {bool large = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: large ? 32 : 24,
          vertical: large ? 16 : 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 2,
        shadowColor: (isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown).withOpacity(0.3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: large ? 18 : 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(String text, VoidCallback onPressed, BuildContext context, {bool large = false}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
        side: BorderSide(
          color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
          width: 2,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: large ? 32 : 24,
          vertical: large ? 16 : 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: large ? 18 : 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
} 