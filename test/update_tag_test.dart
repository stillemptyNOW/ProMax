import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/update_checker.dart';

void main() {
  test('release tags keep the build number around a beta label', () {
    expect(parseReleaseTag('v1.0.3+104'), (version: '1.0.3', build: 104));
    expect(parseReleaseTag('v1.1.0+113-beta.5'), (
      version: '1.1.0',
      build: 113,
    ));
    expect(parseReleaseTag('v1.1.0-beta.6+114'), (
      version: '1.1.0',
      build: 114,
    ));
    expect(parseReleaseTag('v1.1.0-beta.4'), (version: '1.1.0', build: null));
    expect(parseReleaseTag('nightly'), isNull);
  });
}
