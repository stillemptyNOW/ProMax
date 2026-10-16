import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/update_checker.dart';
import 'package:promax/core/utils/update_installer.dart';

final String _digest = 'ab' * 32;

UpdateAsset _asset(String name, {String? sha256}) => UpdateAsset(
  name: name,
  url: 'https://example.invalid/$name',
  size: 1,
  sha256: sha256 ?? _digest,
);

AppUpdateInfo _release(List<UpdateAsset> assets) => AppUpdateInfo(
  version: '2.0.0',
  build: 200,
  tag: 'v2.0.0+200',
  url: 'https://example.invalid/releases/v2.0.0+200',
  notes: '',
  assets: assets,
);

AppUpdateInfo _releaseNamed(List<String> names) =>
    _release([for (final name in names) _asset(name)]);

List<String> _directiveFiles(String script, String directive) {
  final line = script
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.startsWith('$directive='));
  return line.substring(directive.length + 1).split(',');
}

void main() {
  group('newestRelease', () {
    test('picks the highest version and build whatever the list order', () {
      final releases = [
        {'tag_name': 'v2.0.0-beta.4', 'draft': false},
        {'tag_name': 'v2.0.0-beta.3', 'draft': false},
        {'tag_name': 'v2.0.0+201-beta.5', 'draft': false},
        {'tag_name': 'v2.0.0+202-beta.6', 'draft': false},
        {'tag_name': 'v1.9.9+300', 'draft': false},
        {'tag_name': 'nightly', 'draft': false},
      ];
      expect(newestRelease(releases)?['tag_name'], 'v2.0.0+202-beta.6');
    });

    test('a newer version wins over a bigger build of an older one', () {
      final releases = [
        {'tag_name': 'v2.0.0+150'},
        {'tag_name': 'v2.1.0-beta.1'},
      ];
      expect(newestRelease(releases)?['tag_name'], 'v2.1.0-beta.1');
    });

    test('keeps the first listed release when tags tie', () {
      final releases = [
        {'tag_name': 'v2.0.0-beta.4', 'html_url': 'first'},
        {'tag_name': 'v2.0.0-beta.3', 'html_url': 'second'},
      ];
      expect(newestRelease(releases)?['html_url'], 'first');
    });

    test('skips drafts and tags without an app version', () {
      final releases = [
        {'tag_name': 'v3.0.0+300', 'draft': true},
        {'tag_name': 'v2.0.0+200', 'draft': false},
        {'name': 'no tag'},
      ];
      expect(newestRelease(releases)?['tag_name'], 'v2.0.0+200');
      expect(
        newestRelease([
          {'tag_name': 'nightly'},
        ]),
        isNull,
      );
      expect(newestRelease(const []), isNull);
    });

    test('accepts a single release object', () {
      expect(
        newestRelease({'tag_name': 'v2.0.0+200'})?['tag_name'],
        'v2.0.0+200',
      );
    });
  });

  group('Windows installer asset', () {
    test('is the ProMax-Setup executable, not the portable zip', () {
      final info = _releaseNamed([
        'ProMax-Tools.pmx',
        'ProMax-windows-x64.zip',
        'ProMax-2.0.0-promax-arm64-v8a.apk',
        'ProMax-Setup-2.0.0-200.exe',
      ]);
      expect(
        UpdateInstaller.resolveWindowsSetup(info)?.name,
        'ProMax-Setup-2.0.0-200.exe',
      );
    });

    test('is missing when the release only has the zip', () {
      final info = _releaseNamed(['ProMax-windows-x64.zip', 'Other-Setup.exe']);
      expect(UpdateInstaller.resolveWindowsSetup(info), isNull);
    });

    test('is ignored without a published digest', () {
      final info = _release([_asset('ProMax-Setup-2.0.0-200.exe', sha256: '')]);
      expect(UpdateInstaller.resolveWindowsSetup(info), isNull);
    });

    test('keeps its extension when downloaded', () {
      expect(
        UpdateInstaller.packageExtension('ProMax-Setup-2.0.0-200.exe'),
        'exe',
      );
      expect(
        UpdateInstaller.packageExtension('ProMax-ios-unsigned.IPA'),
        'ipa',
      );
      expect(
        UpdateInstaller.packageExtension('ProMax-2.0.0-promax-x86_64.apk'),
        'apk',
      );
    });
  });

  group('in-app install', () {
    final full = _releaseNamed([
      'ProMax-windows-x64.zip',
      'ProMax-Setup-2.0.0-200.exe',
      'ProMax-linux-x64.tar.gz',
      'ProMax-ios-unsigned.ipa',
    ]);
    final desktopOnly = _releaseNamed([
      'ProMax-windows-x64.zip',
      'ProMax-linux-x64.tar.gz',
    ]);

    test('runs the setup only for a copy installed by it', () {
      expect(
        UpdateInstaller.canInstallOn('windows', full, installedBySetup: true),
        isTrue,
      );
      expect(UpdateInstaller.canInstallOn('windows', full), isFalse);
      expect(
        UpdateInstaller.canInstallOn(
          'windows',
          desktopOnly,
          installedBySetup: true,
        ),
        isFalse,
      );
    });

    test('is never offered on Linux or macOS', () {
      for (final os in ['linux', 'macos']) {
        expect(
          UpdateInstaller.canInstallOn(os, full, installedBySetup: true),
          isFalse,
          reason: os,
        );
      }
    });

    test('needs an IPA on iOS and nothing more on Android', () {
      expect(UpdateInstaller.canInstallOn('ios', full), isTrue);
      expect(UpdateInstaller.canInstallOn('ios', desktopOnly), isFalse);
      expect(UpdateInstaller.canInstallOn('android', desktopOnly), isTrue);
    });

    test(
      'is off on this desktop host',
      () => expect(UpdateInstaller.canInstall(full), isFalse),
      skip: Platform.isWindows || Platform.isAndroid || Platform.isIOS,
    );
  });

  group('Inno Setup script', () {
    final script = File('windows/installer/promax.iss').readAsStringSync();

    test('names the setup the way the updater looks for it', () {
      expect(
        script,
        contains('OutputBaseFilename=${UpdateInstaller.windowsSetupPrefix}'),
      );
    });

    test('relaunches ProMax only when the updater asks for it', () {
      expect(
        UpdateInstaller.windowsSetupArguments,
        containsAll(['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART']),
      );
      expect(UpdateInstaller.windowsSetupArguments, contains('/relaunch=1'));
      expect(script, contains("ExpandConstant('{param:relaunch|0}') = '1'"));
      final relaunch = script
          .split('\n')
          .singleWhere((line) => line.contains('Check: RelaunchRequested'));
      expect(relaunch, contains('skipifnotsilent'));
      expect(relaunch, contains('runasoriginaluser'));
      expect(relaunch, contains('nowait'));
      expect(script, contains('function RelaunchRequested: Boolean;'));
    });

    test('closes a running ProMax without restarting it itself', () {
      expect(script, contains('CloseApplications=force'));
      expect(script, contains('RestartApplications=no'));
      expect(script, contains('PrivilegesRequired=lowest'));
    });

    test('ships every wizard image it references', () {
      for (final directive in ['WizardImageFile', 'WizardSmallImageFile']) {
        final files = _directiveFiles(script, directive);
        expect(files, hasLength(3), reason: directive);
        for (final name in files) {
          expect(
            File('windows/installer/$name').existsSync(),
            isTrue,
            reason: name,
          );
        }
      }
    });
  });
}
