import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every English string has a Vietnamese translation and vice versa', () {
    final en = appStrings[AppLang.en]!.keys.toSet();
    final vi = appStrings[AppLang.vi]!.keys.toSet();
    expect(en.difference(vi), isEmpty, reason: 'missing in vi');
    expect(vi.difference(en), isEmpty, reason: 'missing in en');
  });

  test('tr follows the current language and fills arguments', () {
    appLang.value = AppLang.vi;
    expect(tr('login.join'), 'Tham gia mạng');
    expect(tr('restore.failed', {'e': 'x'}), 'Khôi phục thất bại: x');
    appLang.value = AppLang.en;
    expect(tr('login.join'), 'Join the network');
    expect(tr('no.such.key'), 'no.such.key');
  });

  test('device language picks the default', () {
    expect(AppLangController.fromLocale('vi'), AppLang.vi);
    expect(AppLangController.fromLocale('en'), AppLang.en);
    expect(AppLangController.fromLocale('fr'), AppLang.en);
  });
}
