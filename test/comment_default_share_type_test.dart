import 'package:deltanium_app/features/posts/widgets/post_comments_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comments on a public post default to public', () {
    expect(defaultCommentShareType('public'), 'public');
    expect(defaultCommentShareType('Public'), 'public');
  });

  test('comments on a private post default to post-author-only', () {
    expect(defaultCommentShareType('encrypted'), 'author');
    expect(defaultCommentShareType(''), 'author');
  });
}
