import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/services/update_service.dart';

void main() {
  group('UpdateService - Version Comparison', () {
    test('correctly identifies newer semantic versions', () {
      expect(UpdateService.isNewerVersion('2.0.4', '2.0.3'), isTrue);
      expect(UpdateService.isNewerVersion('2.1.0', '2.0.3'), isTrue);
      expect(UpdateService.isNewerVersion('3.0.0', '2.0.3'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.3.1', '2.0.3'), isTrue);
      expect(UpdateService.isNewerVersion('10.0.0', '2.9.9'), isTrue);
    });

    test('correctly identifies older or equal versions', () {
      expect(UpdateService.isNewerVersion('2.0.3', '2.0.3'), isFalse);
      expect(UpdateService.isNewerVersion('2.0.2', '2.0.3'), isFalse);
      expect(UpdateService.isNewerVersion('2.0.1', '2.0.3'), isFalse);
      expect(UpdateService.isNewerVersion('1.9.9', '2.0.3'), isFalse);
      expect(UpdateService.isNewerVersion('2.0.0', '2.0.3'), isFalse);
    });
  });

  group('ReleaseAsset', () {
    test('parses from JSON correctly', () {
      final json = {
        'name': 'musly-setup.exe',
        'browser_download_url':
            'https://github.com/dddevid/Musly/releases/download/v2.1.0/musly-setup.exe',
        'size': 68157440,
      };

      final asset = ReleaseAsset.fromJson(json);
      expect(asset.name, 'musly-setup.exe');
      expect(asset.browserDownloadUrl,
          'https://github.com/dddevid/Musly/releases/download/v2.1.0/musly-setup.exe');
      expect(asset.size, 68157440);
      expect(asset.formattedSize, '65.0 MB');
    });

    test('formattedSize handles null and zero correctly', () {
      const emptyAsset = ReleaseAsset(name: 'test', browserDownloadUrl: 'url');
      expect(emptyAsset.formattedSize, '');

      const zeroAsset =
          ReleaseAsset(name: 'test', browserDownloadUrl: 'url', size: 0);
      expect(zeroAsset.formattedSize, '');
    });
  });

  group('ReleaseInfo', () {
    test('parses ReleaseInfo from GitHub release JSON', () {
      final json = {
        'tag_name': 'v2.1.0',
        'html_url': 'https://github.com/dddevid/Musly/releases/tag/v2.1.0',
        'body': '## What\'s Changed\n* Added Spotify import by @dddevid in #10',
        'assets': [
          {
            'name': 'musly-setup.exe',
            'browser_download_url':
                'https://github.com/dddevid/Musly/releases/download/v2.1.0/musly-setup.exe',
            'size': 52428800,
          },
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://github.com/dddevid/Musly/releases/download/v2.1.0/app-release.apk',
            'size': 31457280,
          },
          {
            'name': 'musly-macos.dmg',
            'browser_download_url':
                'https://github.com/dddevid/Musly/releases/download/v2.1.0/musly-macos.dmg',
            'size': 41943040,
          },
        ],
      };

      final release = ReleaseInfo.fromJson(json);
      expect(release.version, '2.1.0');
      expect(release.tagName, 'v2.1.0');
      expect(release.htmlUrl,
          'https://github.com/dddevid/Musly/releases/tag/v2.1.0');
      expect(release.assets.length, 3);
      expect(release.targetAsset, isNotNull);
    });

    // RD: the Windows branch misses the "-setup.exe" name and falls back to the first asset, so a Windows
    // user's update downloads the macOS .dmg listed before it.
    test('targetAsset selects the matching platform installer',
        skip: Platform.isWindows
            ? false
            : 'targetAsset chooses by the host platform; this case needs Windows',
        () {
      final assets = [
        const ReleaseAsset(
          name: 'musly-macos.dmg',
          browserDownloadUrl: 'dmg-url',
        ),
        const ReleaseAsset(
          name: 'musly-setup.exe',
          browserDownloadUrl: 'exe-url',
        ),
        const ReleaseAsset(
          name: 'app-release.apk',
          browserDownloadUrl: 'apk-url',
        ),
      ];

      final release = ReleaseInfo(
        version: '2.1.0',
        tagName: 'v2.1.0',
        htmlUrl: 'html-url',
        body: 'notes',
        assets: assets,
      );

      final target = release.targetAsset;
      expect(target, isNotNull);
      expect(target!.name, 'musly-setup.exe');
    });
  });

  group('UpdateService - stripMarkdown', () {
    test('cleans markdown headers, bold, italics, and links', () {
      const raw =
          '# Release Notes\n\n**Feature**: Added [new player](https://link.com) and *speed improvements*.\n`Fixed bug`';
      final clean = UpdateService.stripMarkdown(raw);
      expect(clean.contains('#'), isFalse);
      expect(clean.contains('**'), isFalse);
      expect(clean.contains('*speed'), isFalse);
      expect(clean.contains('`'), isFalse);
      expect(clean.contains('https://link.com'), isFalse);
      expect(clean.contains('new player'), isTrue);
      expect(clean.contains('Feature: Added new player and speed improvements.'),
          isTrue);
      expect(clean.contains('Fixed bug'), isTrue);
    });
  });

  group('UpdateService - Startup Check Lifecycle', () {
    test('tracks startup check state correctly', () {
      UpdateService.resetStartupCheck();
      expect(UpdateService.hasCheckedStartup, isFalse);

      UpdateService.markStartupChecked();
      expect(UpdateService.hasCheckedStartup, isTrue);

      UpdateService.resetStartupCheck();
      expect(UpdateService.hasCheckedStartup, isFalse);
    });
  });
}
