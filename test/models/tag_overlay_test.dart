import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/tag_overlay.dart';

void main() {
  // RD: a cleared field ("composer": "") is parsed as absent, so the editor reads the song as unedited and hides
  // the revert, though the server clears that tag. The wire format is navidrome's unimouseTagOverlay response.
  test('keeps a cleared field apart from an absent one', () {
    final cleared = TagOverlay.fromJson({'id': '1', 'composer': ''});
    final none = TagOverlay.fromJson({'id': '1'});

    expect(cleared.composer, '');
    expect(cleared.title, isNull);
    expect(cleared.hasEdit, isTrue);
    expect(none.hasEdit, isFalse);
  });
}
