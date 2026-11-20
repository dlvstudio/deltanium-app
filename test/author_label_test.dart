import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/utils/author_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = '02c18dbdac636a944fdc0e3785ccd5c99eae14227b5b23d227f24b07c7b179861d';
  const other = '02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';

  test('own comments and posts read "You" in the current language', () {
    appLang.value = AppLang.en;
    expect(authorLabel(me, me), 'You');
    appLang.value = AppLang.vi;
    expect(authorLabel(me, me), 'Bạn');
    appLang.value = AppLang.en;
  });

  test('others show a short key, or their name when they shared it', () {
    expect(authorLabel(other, me), '02c6047f...709ee5');
    expect(authorLabel(other, me, name: 'Lan'), 'Lan');
    expect(authorLabel(null, me), 'Unknown');
  });
}
