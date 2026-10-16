import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:promax/core/security/file_name_policy.dart';
import 'package:promax/core/security/incoming_paths.dart';
import 'package:promax/core/security/mark_of_the_web.dart';
import 'package:promax/core/security/url_policy.dart';
import 'package:promax/core/utils/external_tool.dart';
import 'package:promax/frontend/screens/webapp/web_app_origin_policy.dart';

void main() {
  group('sanitizeFileName', () {
    test('keeps ordinary names intact', () {
      expect(sanitizeFileName('report 2026.pdf'), 'report 2026.pdf');
      expect(sanitizeFileName('отчёт.docx'), 'отчёт.docx');
    });

    test('never lets a name climb out of its folder', () {
      for (final raw in [
        '../../etc/passwd',
        r'..\..\Windows\System32\evil.dll',
        '/absolute/path.txt',
        r'C:\Users\someone\file.txt',
        '..',
        '.',
      ]) {
        final name = sanitizeFileName(raw);
        expect(name.contains('/'), isFalse, reason: raw);
        expect(name.contains(r'\'), isFalse, reason: raw);
        expect(name.contains(':'), isFalse, reason: raw);
        expect(name == '..' || name == '.', isFalse, reason: raw);
        expect(name.startsWith('.'), isFalse, reason: raw);
      }
    });

    test('replaces characters Windows forbids and control characters', () {
      expect(sanitizeFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
      expect(sanitizeFileName('line\nbreak\u0000.txt'), 'line_break_.txt');
    });

    test('drops direction overrides that disguise extensions', () {
      final name = sanitizeFileName('photo\u202Egpj.exe');
      expect(name, 'photogpj.exe');
      expect(isRiskyFileName('photo\u202Egpj.exe'), isTrue);
    });

    test('strips trailing dots and spaces', () {
      expect(sanitizeFileName('setup.exe. . '), 'setup.exe');
      expect(sanitizeFileName('  notes.txt  '), 'notes.txt');
      expect(isRiskyFileName('setup.exe...'), isTrue);
    });

    test('defuses reserved Windows device names', () {
      for (final raw in ['CON', 'con.txt', 'Nul .log', 'COM1.dat', 'lpt9']) {
        expect(sanitizeFileName(raw).startsWith('_'), isTrue, reason: raw);
      }
      expect(sanitizeFileName('console.txt'), 'console.txt');
    });

    test('limits the length but keeps the extension', () {
      final name = sanitizeFileName('${'я' * 400}.pdf');
      expect(utf8.encode(name).length, lessThanOrEqualTo(maxFileNameBytes));
      expect(name.endsWith('.pdf'), isTrue);
    });

    test('falls back when nothing usable is left', () {
      expect(sanitizeFileName('...'), 'file');
      expect(sanitizeFileName('', fallback: 'download'), 'download');
    });

    test('is stable when applied twice', () {
      for (final raw in ['CON', '../x', 'a:b', '${'x' * 300}.zip', 'ok.txt']) {
        final once = sanitizeFileName(raw);
        expect(sanitizeFileName(once), once, reason: raw);
      }
    });
  });

  group('risky files', () {
    test('flags programs, scripts and shortcuts', () {
      for (final name in [
        'invoice.pdf.exe',
        'run.BAT',
        'script.ps1',
        'macro.vbs',
        'payload.js',
        'link.lnk',
        'installer.msi',
        'app.apk',
        'tool.jar',
        'disk.iso',
        'start.command',
        'install.sh',
      ]) {
        expect(isRiskyFileName(name), isTrue, reason: name);
      }
      expect(riskyExtensionOf('Setup.EXE'), '.exe');
    });

    test('leaves documents and media alone', () {
      for (final name in [
        'photo.jpg',
        'notes.txt',
        'report.pdf',
        'table.xlsx',
        'archive.zip',
        'song.mp3',
        'noextension',
      ]) {
        expect(isRiskyFileName(name), isFalse, reason: name);
      }
    });
  });

  group('target files', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('promax_sandbox_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('stay inside the chosen folder', () {
      final file = fileInside(dir.path, '../../outside.txt');
      expect(p.isWithin(dir.path, file.path), isTrue);
    });

    test('never overwrite an existing file', () async {
      await File(p.join(dir.path, 'a.txt')).writeAsString('one');
      await File(p.join(dir.path, 'a (2).txt')).writeAsString('two');
      final next = await availableFileIn(dir.path, 'a.txt');
      expect(p.basename(next.path), 'a (3).txt');
    });
  });

  group('external links', () {
    test('allow web, mail, phone and sms links', () {
      for (final url in [
        'https://example.com/page',
        'http://example.com',
        'mailto:someone@example.com',
        'tel:+70000000000',
        'sms:+70000000000',
      ]) {
        expect(parseExternalUri(url), isNotNull, reason: url);
      }
    });

    test('block links that reach files, scripts or system handlers', () {
      for (final url in [
        'file:///C:/Windows/System32/calc.exe',
        r'\\attacker\share\doc.lnk',
        'javascript:alert(1)',
        'data:text/html,hello',
        'intent://scan#Intent;scheme=zxing;end',
        'smb://attacker/share',
        'ms-msdt:/id PCWDiagnostic',
        'search-ms:query=x',
        'ms-settings:privacy',
        'vbscript:msgbox',
        'https:///no-host',
        'tel://host/path',
      ]) {
        expect(parseExternalUri(url), isNull, reason: url);
      }
    });

    test('recognise the app deep link schemes', () {
      expect(isAppLinkUri(Uri.parse('promax://open?chatId=1')), isTrue);
      expect(isAppLinkUri(Uri.parse('MAX://max.ru/x')), isTrue);
      expect(isAppLinkUri(Uri.parse('https://max.ru')), isFalse);
    });

    test('normalise web origins', () {
      expect(
        webOriginOf(Uri.parse('HTTPS://Example.COM/a?b')),
        'https://example.com:443',
      );
      expect(webOriginOf(Uri.parse('file:///tmp/x')), isNull);
    });
  });

  group('mini-app origins', () {
    test('trust only the launch origin of a third-party app', () {
      final policy = WebAppOriginPolicy(
        Uri.parse('https://app.example.org/start?x=1'),
      );
      expect(policy.trusts(Uri.parse('https://app.example.org/other')), isTrue);
      expect(policy.trusts(Uri.parse('http://app.example.org/')), isFalse);
      expect(policy.trusts(Uri.parse('https://evil.example.org/')), isFalse);
      expect(policy.trusts(Uri.parse('https://max.ru/')), isFalse);
      expect(policy.trusts(null), isFalse);
    });

    test('let first-party apps move between MAX hosts', () {
      final policy = WebAppOriginPolicy(
        Uri.parse('https://digital-id.max.ru/'),
      );
      expect(policy.trusts(Uri.parse('https://web.max.ru/')), isTrue);
      expect(policy.trusts(Uri.parse('https://id.oneme.ru/')), isTrue);
      expect(policy.trusts(Uri.parse('https://max.ru.example.org/')), isFalse);
      expect(policy.trusts(Uri.parse('http://web.max.ru/')), isFalse);
    });

    test('a visited site may be browsed but never gets the bridge', () {
      final policy = WebAppOriginPolicy(Uri.parse('https://app.example.org/'));
      final other = Uri.parse('https://login.example.net/auth');
      expect(policy.mayNavigate(other), isFalse);
      policy.allowVisit(other);
      expect(policy.mayNavigate(other), isTrue);
      expect(policy.trusts(other), isFalse);
    });
  });

  group('pasted paths', () {
    test('reject network shares and the app private folder', () {
      final roots = [r'C:\Users\u\AppData\Roaming\promax'];
      bool ok(String path) =>
          isPastableLocalPath(path, privateRoots: roots, windows: true);
      expect(ok(r'C:\Users\u\Pictures\cat.png'), isTrue);
      expect(ok(r'\\attacker\share\cat.png'), isFalse);
      expect(ok('//attacker/share/cat.png'), isFalse);
      expect(ok(r'\\?\UNC\attacker\share\x'), isFalse);
      expect(ok(r'C:\Users\u\AppData\Roaming\promax\promax.db'), isFalse);
      expect(ok(r'relative\cat.png'), isFalse);
    });

    test('reject the private folder on POSIX desktops', () {
      final roots = ['/home/u/.local/share/promax'];
      bool ok(String path) =>
          isPastableLocalPath(path, privateRoots: roots, windows: false);
      expect(ok('/home/u/Pictures/cat.png'), isTrue);
      expect(ok('/home/u/.local/share/promax/promax.db'), isFalse);
      expect(ok('/home/u/.local/share/promax/../promax/x'), isFalse);
    });
  });

  group('external tools', () {
    test('look next to the app and in absolute PATH entries only', () {
      final candidates = ExternalTool.candidates(
        'ffmpeg',
        executable: r'C:\Program Files\ProMax\ProMax.exe',
        searchPath: r'.;C:\tools\ffmpeg\bin;;relative\bin;\\server\bin;"C:\q"',
        windows: true,
      );
      expect(candidates, [
        r'C:\Program Files\ProMax\ffmpeg.exe',
        r'C:\tools\ffmpeg\bin\ffmpeg.exe',
        r'C:\q\ffmpeg.exe',
      ]);
    });

    test('use plain names on POSIX', () {
      final candidates = ExternalTool.candidates(
        'ffprobe',
        executable: '/opt/promax/promax',
        searchPath: '/usr/bin::bin',
        windows: false,
      );
      expect(candidates, ['/opt/promax/ffprobe', '/usr/bin/ffprobe']);
    });
  });

  test('marks downloads with the internet zone', () {
    expect(MarkOfTheWeb.zoneIdentifier, contains('ZoneId=3'));
    expect(
      MarkOfTheWeb.streamPathOf(r'C:\d\a.exe'),
      r'C:\d\a.exe:Zone.Identifier',
    );
  });
}
