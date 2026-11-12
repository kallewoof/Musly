import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/widgets/common/lan_indicator_band.dart';

import '../bootstrap.dart';

void main() {
  initializeTestEnvironment();

  group('SubsonicService.isLocalAddress', () {
    // RD: a local name or private range is missed, so the band stays dark at home and says nothing about the
    // route actually in use.
    test('counts local names and private ranges as local', () {
      for (final url in [
        'http://nas.local:4533',
        'http://nas:4533',
        'http://localhost:4533',
        'http://127.0.0.1:4533',
        'http://10.1.2.3',
        'http://172.16.0.1',
        'http://172.31.255.254',
        'http://192.168.0.10:4533',
        'http://169.254.3.4',
        'http://[fd12:3456::1]:4533',
        'http://[fe80::1]',
      ]) {
        expect(SubsonicService.isLocalAddress(url), isTrue, reason: url);
      }
    });

    // RD: the 172.16.0.0/12 check matches all of 172.x, or a public name counts as local, so the band lights
    // up while every request goes through Cloudflare.
    test('does not count public names or addresses as local', () {
      for (final url in [
        'https://music.example.com',
        'http://172.15.0.1',
        'http://172.32.0.1',
        'http://172.217.1.1',
        'http://8.8.8.8',
        'http://[2606:4700::1111]',
        '',
      ]) {
        expect(SubsonicService.isLocalAddress(url), isFalse, reason: url);
      }
    });
  });

  // RD: the band reads the route once and never listens again, so after the phone leaves home it keeps
  // claiming the LAN while every request goes through Cloudflare.
  testWidgets('the band follows the route as it changes', (tester) async {
    final service = SubsonicService();
    Future<void> useServer(String url) async {
      await tester.runAsync(() => service.configure(
          ServerConfig(serverUrl: url, username: 'u', password: 'p')));
      await tester.pumpAndSettle();
    }

    double opacity() => tester
        .widget<AnimatedOpacity>(find.descendant(
            of: find.byType(LanIndicatorBand),
            matching: find.byType(AnimatedOpacity)))
        .opacity;

    await useServer('https://music.example.com');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LanIndicatorBand(service: service))));
    expect(opacity(), 0);

    await useServer('http://nas.local:4533');
    expect(opacity(), 1);

    await useServer('https://music.example.com');
    expect(opacity(), 0);
  });

  // RD: the band is placed at the very top pixel row, which on a phone is the status bar strip at the rounded
  // top edge, so it never shows there.
  testWidgets('the overlay puts the band just below the status bar',
      (tester) async {
    final service = SubsonicService();
    Future<Offset> bandTopLeft(double statusBar) async {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
            size: const Size(430, 932),
            padding: EdgeInsets.only(top: statusBar)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: LanIndicatorOverlay(
              service: service, child: const SizedBox.expand()),
        ),
      ));
      return tester.getTopLeft(find.byType(LanIndicatorBand));
    }

    expect(await bandTopLeft(59), const Offset(0, 59));
    expect(tester.getSize(find.byType(LanIndicatorBand)).width,
        tester.getSize(find.byType(LanIndicatorOverlay)).width);
    expect(await bandTopLeft(0), Offset.zero);
  });
}
