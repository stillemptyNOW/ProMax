import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/update_channel.dart';
import 'package:promax/core/utils/update_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final releases = [
    {'tag_name': 'v1.2.0+200-beta.1', 'prerelease': true},
    {'tag_name': 'v1.1.0+190-beta.9', 'prerelease': false},
    {'tag_name': 'v1.0.0+100', 'prerelease': false},
  ];
  test('stable channel excludes GitHub and legacy tag betas', () {
    expect(
      newestRelease(releases, includePrereleases: false)!['tag_name'],
      'v1.0.0+100',
    );
    expect(
      newestRelease(releases, includePrereleases: true)!['tag_name'],
      'v1.2.0+200-beta.1',
    );
  });
  test('no stable release yet is not a failed update check', () {
    expect(
      updateFromReleases(
        releases.take(2).toList(),
        currentVersion: '1.0.0',
        currentBuild: 90,
        includePrereleases: false,
      ),
      isNull,
    );
  });
  test('stable release notes contain no beta announcements', () {
    final notes = releaseNotesNewerThan(
      releases,
      currentVersion: '0.9.0',
      currentBuild: 1,
      includePrereleases: false,
    );
    expect(notes.map((note) => note.tag), ['v1.0.0+100']);
  });
  test('beta channel is off by default and opt-in persists', () async {
    SharedPreferences.setMockInitialValues({});
    await UpdateChannel.load();
    expect(UpdateChannel.beta.value, isFalse);
    await UpdateChannel.setBeta(true);
    await UpdateChannel.load();
    expect(UpdateChannel.beta.value, isTrue);
  });
}
