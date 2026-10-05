import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/build_profile.dart';
import 'package:promax/core/config/update_config.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('${platform.name} keeps the update check outside store builds', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(BuildProfile.selfUpdate, !BuildProfile.isStore);
      expect(UpdateConfig.isConfigured, isTrue);
      expect(UpdateConfig.manifestUri.host, 'api.github.com');
      expect(UpdateConfig.downloadsPage, contains('stillemptyNOW/ProMax'));
    });
  }
}
