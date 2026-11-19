import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Signed-out landing page. Mirrors deltanium.com: private to use, paid to run.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static final Uri _earnUrl = Uri.parse('https://deltanium.com/#economy');
  static final Uri _siteUrl = Uri.parse('https://deltanium.com');

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context) {
        final width = MediaQuery.sizeOf(context).width;
        final wide = width >= 960;
        final pad = wide ? 40.0 : 20.0;
        return Scaffold(
          backgroundColor: Brand.ink,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Brand.maxWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(onLogin: () => context.go(AppRoutes.login)),
                        SizedBox(height: wide ? 72 : 32),
                        wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(flex: 6, child: _Hero(wide: wide)),
                                  const SizedBox(width: 56),
                                  const Expanded(flex: 5, child: _Banner()),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Hero(wide: wide),
                                  const SizedBox(height: 32),
                                  const _Banner(),
                                ],
                              ),
                        SizedBox(height: wide ? 96 : 56),
                        _SectionTitle(kicker: tr('landing.why.kicker'), title: tr('landing.why.title')),
                        const SizedBox(height: 24),
                        _Cards(items: [
                          _CardData(Icons.lock_outline, tr('landing.c1.title'), tr('landing.c1.desc')),
                          _CardData(Icons.chat_bubble_outline, tr('landing.c2.title'), tr('landing.c2.desc')),
                          _CardData(Icons.key_outlined, tr('landing.c3.title'), tr('landing.c3.desc')),
                        ]),
                        SizedBox(height: wide ? 96 : 56),
                        _SectionTitle(kicker: tr('landing.earn.kicker'), title: tr('landing.earn.title')),
                        const SizedBox(height: 24),
                        _Cards(items: [
                          _CardData(Icons.storage_outlined, tr('landing.e1.title'), tr('landing.e1.desc')),
                          _CardData(Icons.verified_outlined, tr('landing.e2.title'), tr('landing.e2.desc')),
                          _CardData(Icons.favorite_border, tr('landing.e3.title'), tr('landing.e3.desc')),
                        ]),
                        const SizedBox(height: 20),
                        Text(tr('landing.earn.note'), style: _muted.copyWith(fontSize: 13)),
                        SizedBox(height: wide ? 96 : 56),
                        _FinalCta(onJoin: () => context.go(AppRoutes.login)),
                        const SizedBox(height: 48),
                        const Divider(color: Brand.line, height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            runSpacing: 8,
                            spacing: 16,
                            children: [
                              Text(tr('landing.footer'), style: _muted.copyWith(fontSize: 13)),
                              InkWell(
                                onTap: () => _open(_siteUrl),
                                child: Text('deltanium.com', style: _muted.copyWith(fontSize: 13, color: Brand.sand)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _open(Uri url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  static Future<void> openEarn() => _open(_earnUrl);
}

final TextStyle _muted = GoogleFonts.manrope(color: Brand.muted, height: 1.5);

TextStyle _display(double size) =>
    GoogleFonts.syne(color: Brand.text, fontWeight: FontWeight.w800, fontSize: size, letterSpacing: -0.03 * size, height: 1.1);

class _Header extends StatelessWidget {
  const _Header({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Deltanium', style: _display(22)),
              TextSpan(text: '.', style: _display(22).copyWith(color: Brand.sand)),
            ]),
          ),
          const Spacer(),
          const LangSwitch(color: Brand.muted, activeColor: Brand.sand),
          const SizedBox(width: 4),
          IconButton(
            tooltip: tr('landing.login'),
            onPressed: onLogin,
            icon: const Icon(Icons.login, color: Brand.sand),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('landing.hero.title'), style: _display(wide ? 52 : 34)),
        const SizedBox(height: 18),
        Text(tr('landing.hero.sub'), style: _muted.copyWith(fontSize: wide ? 18 : 16)),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: () => context.go(AppRoutes.login),
              style: FilledButton.styleFrom(
                backgroundColor: Brand.sand,
                foregroundColor: Brand.ink,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
                textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              child: Text(tr('landing.cta.user')),
            ),
            OutlinedButton(
              onPressed: LandingScreen.openEarn,
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.sandBright,
                side: const BorderSide(color: Brand.sand),
                backgroundColor: Brand.sand.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
                textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              child: Text(tr('landing.cta.node')),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Divider(color: Brand.line, height: 1),
        const SizedBox(height: 18),
        Wrap(
          spacing: 28,
          runSpacing: 14,
          children: [
            _Stat(value: '80%', label: tr('landing.stat1')),
            _Stat(value: '90%', label: tr('landing.stat2')),
            _Stat(value: '1 D = 1 VND', label: tr('landing.stat3')),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: _display(20).copyWith(color: Brand.sandBright)),
          const SizedBox(height: 2),
          Text(label, style: _muted.copyWith(fontSize: 13, height: 1.35)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius * 3),
            border: Border.all(color: Brand.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/images/banner.png', fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.kicker, required this.title});

  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: GoogleFonts.manrope(color: Brand.sand, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1.6),
        ),
        const SizedBox(height: 10),
        Text(title, style: _display(wide ? 36 : 26)),
      ],
    );
  }
}

class _CardData {
  const _CardData(this.icon, this.title, this.desc);

  final IconData icon;
  final String title;
  final String desc;
}

class _Cards extends StatelessWidget {
  const _Cards({required this.items});

  final List<_CardData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 860 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final it in items)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Brand.panel.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(Brand.radius),
                    border: Border.all(color: Brand.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(it.icon, color: Brand.sand, size: 26),
                      const SizedBox(height: 14),
                      Text(it.title, style: _display(17)),
                      const SizedBox(height: 8),
                      Text(it.desc, style: _muted.copyWith(fontSize: 14)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FinalCta extends StatelessWidget {
  const _FinalCta({required this.onJoin});

  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Container(
      padding: EdgeInsets.all(wide ? 40 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radius * 2),
        border: Border.all(color: Brand.line),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2822), Color(0xFF121A16)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('landing.final.title'), style: _display(wide ? 32 : 24)),
          const SizedBox(height: 12),
          Text(tr('landing.final.sub'), style: _muted.copyWith(fontSize: 15)),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: onJoin,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.sand,
                  foregroundColor: Brand.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
                  textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                child: Text(tr('landing.cta.user')),
              ),
              TextButton(
                onPressed: LandingScreen.openEarn,
                style: TextButton.styleFrom(
                  foregroundColor: Brand.sand,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                child: Text(tr('landing.cta.nodeMore')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
