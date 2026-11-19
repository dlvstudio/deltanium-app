import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI language for the signed-out screens (landing + login).
enum AppLang { en, vi }

/// Current language. Saved per device; the first visit follows the device/browser language.
class AppLangController extends ValueNotifier<AppLang> {
  AppLangController() : super(AppLang.en);

  static const prefsKey = 'deltanium.lang';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefsKey);
      value = saved != null ? parse(saved) : fromLocale(PlatformDispatcher.instance.locale.languageCode);
    } catch (_) {
      value = fromLocale(PlatformDispatcher.instance.locale.languageCode);
    }
  }

  Future<void> set(AppLang lang) async {
    value = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, lang.name);
    } catch (_) {}
  }

  static AppLang parse(String code) => code.toLowerCase() == 'vi' ? AppLang.vi : AppLang.en;
  static AppLang fromLocale(String languageCode) => parse(languageCode);
}

final appLang = AppLangController();

/// Text for [key] in the current language; falls back to English, then to the key itself.
String tr(String key, [Map<String, String> args = const {}]) {
  var s = appStrings[appLang.value]?[key] ?? appStrings[AppLang.en]![key] ?? key;
  args.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

/// Rebuilds [builder] whenever the language changes.
class AppLangBuilder extends StatelessWidget {
  const AppLangBuilder({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppLang>(valueListenable: appLang, builder: (context, _, __) => builder(context));
}

/// Compact "VI | EN" switch.
class LangSwitch extends StatelessWidget {
  const LangSwitch({super.key, this.color, this.activeColor});

  final Color? color;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final active = activeColor ?? Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLang,
      builder: (context, current, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(AppLang.vi, 'VI', 'Tiếng Việt', current, base, active),
          Text('|', style: TextStyle(color: base.withValues(alpha: 0.5))),
          _btn(AppLang.en, 'EN', 'English', current, base, active),
        ],
      ),
    );
  }

  Widget _btn(AppLang lang, String label, String tooltip, AppLang current, Color base, Color active) {
    final selected = lang == current;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: selected ? null : () => appLang.set(lang),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? active : base,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const Map<AppLang, Map<String, String>> appStrings = {
  AppLang.en: {
    // Landing
    'landing.login': 'Log in',
    'landing.hero.title': 'Private to use. Paid to run.',
    'landing.hero.sub': 'Post and chat with no one watching — not even us. Got a spare machine? Run a node and earn 80% of the storage fees it handles.',
    'landing.cta.user': 'Become a user',
    'landing.cta.node': 'Run a node, get paid',
    'landing.cta.nodeMore': 'How node income works →',
    'landing.stat1': 'of storage fees go to Store nodes',
    'landing.stat2': 'of subscriptions and tips go to creators',
    'landing.stat3': 'backed 1:1, cash out to VND',
    'landing.why.kicker': 'Why Deltanium',
    'landing.why.title': 'Social media that does not own you.',
    'landing.c1.title': 'Private means private',
    'landing.c1.desc': 'Your device locks what you share. Only the people you choose can open it — not us, not advertisers.',
    'landing.c2.title': 'Chat, just between you',
    'landing.c2.desc': 'Talk one-to-one, or leave a message for later. What two people say stays between two people.',
    'landing.c3.title': 'Your account, your keys',
    'landing.c3.desc': 'No password stored anywhere. A 12-word recovery phrase brings your identity back on any device.',
    'landing.earn.kicker': 'Earn with the network',
    'landing.earn.title': 'No ads. The money goes to the people who power it.',
    'landing.e1.title': 'Run a Store node',
    'landing.e1.desc': 'Lend disk space for encrypted copies. Get 80% of storage fees and 85% of bandwidth fees, paid monthly.',
    'landing.e2.title': 'Run a Block Creator',
    'landing.e2.desc': 'Confirm transactions and write them into the chain. The fees from each block go to the node that writes it.',
    'landing.e3.title': 'Create content',
    'landing.e3.desc': 'Set a monthly subscription or take tips. You keep 90%.',
    'landing.earn.note': '1 D = 1 VND, backed 1:1. Node income depends on real usage and is not guaranteed.',
    'landing.final.title': 'Come for friends. Stay for privacy. Run a node to share in it.',
    'landing.final.sub': 'Your account starts on this device, free — 200 MB of storage included.',
    'landing.footer': '© 2026 Deltanium',
    // Login – brand panel
    'login.brand.line': 'Your social life — without selling your privacy.',
    'login.brand.sub': 'Post, follow friends, and chat on a network you actually own. Your keys stay with you.',
    'login.point.keys': 'You hold the keys',
    'login.point.private': 'Private means private',
    'login.point.grow': 'A network you help grow',
    // Login – auth card
    'login.welcomeBack': 'Welcome back',
    'login.join': 'Join the network',
    'login.welcomeBack.sub': 'Continue with an identity saved on this device, or restore with your recovery phrase.',
    'login.join.sub':
        'Create your identity on this device. Your keys stay with you — we never read your private content.',
    'login.onDevice': 'On this device',
    'login.createAnother': 'Create another account',
    'login.becomeUser': 'Become a user',
    'login.restoreWithPhrase': 'Restore with recovery phrase',
    'login.err.auth': 'Failed to authenticate. API may be unavailable.',
    'login.err.generic': 'An error occurred: {e}',
    // Restore dialog
    'restore.title': 'Restore identity',
    'restore.sub':
        'Enter the 12-word recovery phrase from when you created the account. No password is stored on the network.',
    'restore.phrase': 'Recovery phrase',
    'restore.invalid': 'Invalid recovery phrase.',
    'restore.notFound': 'No registered account found for this phrase.',
    'restore.failed': 'Restore failed: {e}',
    'restore.submit': 'Restore & continue',
    // Register dialog
    'register.title': 'Create account',
    'register.saveKeys': 'Save your keys',
    'register.sub': 'Your identity starts on this device. We never store a password — keep your recovery phrase safe.',
    'register.saveKeys.sub': 'Write these words down offline. Anyone with them can control this identity.',
    'register.email': 'Email',
    'register.email.empty': 'Enter your email',
    'register.email.invalid': 'Enter a valid email',
    'register.name': 'Full name',
    'register.name.empty': 'Enter your full name',
    'register.dob': 'Date of birth',
    'register.dob.select': 'Select date',
    'register.dob.missing': 'Please select your date of birth.',
    'register.bio': 'Bio (optional)',
    'register.avatar': 'Avatar URL (optional)',
    'register.failed': 'Registration failed. Please try again.',
    'register.submit': 'Create account',
    'register.phrase': 'Recovery phrase',
    'register.phraseCopied': 'Recovery phrase copied',
    'register.copyPhrase': 'Copy phrase',
    'register.publicKey': 'Public key',
    'register.saved': 'Saved on this device',
    'register.saveOnDevice': 'Save on this device',
    'register.created': 'Account created. Keep your recovery phrase safe.',
    'register.continue': 'Continue to the app',
  },
  AppLang.vi: {
    // Landing
    'landing.login': 'Đăng nhập',
    'landing.hero.title': 'Dùng thì riêng tư. Góp máy thì có thu nhập.',
    'landing.hero.sub': 'Đăng bài, chat mà không ai soi — kể cả chúng tôi. Có máy rảnh? Chạy một node và nhận 80% phí lưu trữ mà node đó xử lý.',
    'landing.cta.user': 'Trở thành người dùng',
    'landing.cta.node': 'Chạy node, có thu nhập',
    'landing.cta.nodeMore': 'Thu nhập từ node hoạt động thế nào →',
    'landing.stat1': 'phí lưu trữ trả cho node Store',
    'landing.stat2': 'tiền đăng ký và tip về tay nhà sáng tạo',
    'landing.stat3': 'bảo chứng 1:1, rút được ra VND',
    'landing.why.kicker': 'Vì sao chọn Deltanium',
    'landing.why.title': 'Mạng xã hội không sở hữu bạn.',
    'landing.c1.title': 'Riêng tư là riêng tư',
    'landing.c1.desc': 'Máy bạn khóa những gì bạn chia sẻ. Chỉ người bạn chọn mới mở được — không phải chúng tôi, không phải nhà quảng cáo.',
    'landing.c2.title': 'Chat, chỉ hai người biết',
    'landing.c2.desc': 'Nói chuyện trực tiếp, hoặc để lại tin nhắn cho sau. Chuyện hai người, chỉ hai người biết.',
    'landing.c3.title': 'Tài khoản của bạn, khóa của bạn',
    'landing.c3.desc': 'Không lưu mật khẩu ở đâu cả. Cụm từ khôi phục 12 từ đưa danh tính của bạn trở lại trên bất kỳ máy nào.',
    'landing.earn.kicker': 'Kiếm thu nhập cùng mạng',
    'landing.earn.title': 'Không quảng cáo. Tiền về tay người góp sức.',
    'landing.e1.title': 'Chạy node Store',
    'landing.e1.desc': 'Cho mạng mượn ổ cứng để giữ bản sao đã mã hóa. Nhận 80% phí lưu trữ và 85% phí băng thông, trả hằng tháng.',
    'landing.e2.title': 'Chạy Block Creator',
    'landing.e2.desc': 'Xác nhận giao dịch và ghi vào chuỗi khối. Phí của mỗi block được trả cho node ghi block đó.',
    'landing.e3.title': 'Sáng tạo nội dung',
    'landing.e3.desc': 'Đặt gói đăng ký hằng tháng hoặc nhận tip. Bạn giữ 90%.',
    'landing.earn.note': '1 D = 1 VND, bảo chứng 1:1. Thu nhập của node phụ thuộc vào mức sử dụng thực tế và không được đảm bảo.',
    'landing.final.title': 'Đến vì bạn bè. Ở lại vì riêng tư. Góp máy để cùng hưởng.',
    'landing.final.sub': 'Tài khoản bắt đầu ngay trên máy này, miễn phí — kèm 200 MB lưu trữ.',
    'landing.footer': '© 2026 Deltanium',
    // Login – brand panel
    'login.brand.line': 'Đời sống xã hội của bạn — không bán quyền riêng tư.',
    'login.brand.sub': 'Đăng bài, theo dõi bạn bè và chat trên mạng thuộc về bạn. Khóa nằm trên máy bạn.',
    'login.point.keys': 'Bạn giữ khóa',
    'login.point.private': 'Riêng tư là riêng tư',
    'login.point.grow': 'Mạng do chính bạn cùng phát triển',
    // Login – auth card
    'login.welcomeBack': 'Chào mừng trở lại',
    'login.join': 'Tham gia mạng',
    'login.welcomeBack.sub': 'Tiếp tục với danh tính đã lưu trên máy này, hoặc khôi phục bằng cụm từ khôi phục.',
    'login.join.sub':
        'Tạo danh tính trên máy này. Khóa nằm trên máy bạn — chúng tôi không đọc nội dung riêng tư của bạn.',
    'login.onDevice': 'Trên máy này',
    'login.createAnother': 'Tạo tài khoản khác',
    'login.becomeUser': 'Trở thành người dùng',
    'login.restoreWithPhrase': 'Khôi phục bằng cụm từ khôi phục',
    'login.err.auth': 'Xác thực thất bại. API có thể đang không truy cập được.',
    'login.err.generic': 'Đã xảy ra lỗi: {e}',
    // Restore dialog
    'restore.title': 'Khôi phục danh tính',
    'restore.sub':
        'Nhập cụm từ khôi phục 12 từ bạn nhận khi tạo tài khoản. Mạng không lưu mật khẩu nào.',
    'restore.phrase': 'Cụm từ khôi phục',
    'restore.invalid': 'Cụm từ khôi phục không hợp lệ.',
    'restore.notFound': 'Không tìm thấy tài khoản nào đã đăng ký với cụm từ này.',
    'restore.failed': 'Khôi phục thất bại: {e}',
    'restore.submit': 'Khôi phục và tiếp tục',
    // Register dialog
    'register.title': 'Tạo tài khoản',
    'register.saveKeys': 'Lưu khóa của bạn',
    'register.sub':
        'Danh tính của bạn bắt đầu trên máy này. Chúng tôi không lưu mật khẩu — hãy giữ kỹ cụm từ khôi phục.',
    'register.saveKeys.sub': 'Hãy chép các từ này ra giấy. Ai có chúng đều điều khiển được danh tính này.',
    'register.email': 'Email',
    'register.email.empty': 'Nhập email của bạn',
    'register.email.invalid': 'Nhập email hợp lệ',
    'register.name': 'Họ và tên',
    'register.name.empty': 'Nhập họ và tên',
    'register.dob': 'Ngày sinh',
    'register.dob.select': 'Chọn ngày',
    'register.dob.missing': 'Vui lòng chọn ngày sinh.',
    'register.bio': 'Giới thiệu (không bắt buộc)',
    'register.avatar': 'URL ảnh đại diện (không bắt buộc)',
    'register.failed': 'Đăng ký thất bại. Vui lòng thử lại.',
    'register.submit': 'Tạo tài khoản',
    'register.phrase': 'Cụm từ khôi phục',
    'register.phraseCopied': 'Đã sao chép cụm từ khôi phục',
    'register.copyPhrase': 'Sao chép cụm từ',
    'register.publicKey': 'Khóa công khai',
    'register.saved': 'Đã lưu trên máy này',
    'register.saveOnDevice': 'Lưu trên máy này',
    'register.created': 'Đã tạo tài khoản. Hãy giữ kỹ cụm từ khôi phục.',
    'register.continue': 'Vào app',
  },
};
