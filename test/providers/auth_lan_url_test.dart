import 'package:flutter_test/flutter_test.dart';
import 'package:musly/providers/auth_provider.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../fake_queue_server.dart';

/// Setting a saved server's LAN address: two local servers stand in for the public and the LAN address.
void main() {
  initializeTestEnvironment();

  late FakeQueueServer public;
  late FakeQueueServer lan;
  late SubsonicService service;
  late AuthProvider auth;

  String url(FakeQueueServer s) => 'http://127.0.0.1:${s.port}';

  setUp(() async {
    public = FakeQueueServer();
    lan = FakeQueueServer();
    await public.start();
    await lan.start();
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    service = SubsonicService();
    auth = AuthProvider(service, StorageService());
    expect(
        await auth.login(serverUrl: url(public), username: 'u', password: 'p'),
        isTrue);
  });

  tearDown(() async {
    await public.stop();
    await lan.stop();
  });

  // RD: the address is saved but the route is not re-decided, so it has no effect until a restart; or it is
  // saved with the server but not its profile, so switching profiles loses it.
  test('a LAN address set later is used at once and kept with the server',
      () async {
    await auth.setLanUrl(' ${url(lan)} ');

    expect(service.route.value, url(lan));
    expect((await StorageService().getServerConfig())!.lanUrl, url(lan));
    expect((await StorageService().getSavedProfiles()).single.lanUrl, url(lan));
  });

  // RD: clearing goes through copyWith, which keeps the old value for a missing one, so a removed LAN address is still tried.
  test('clearing the LAN address goes back to the public address', () async {
    await auth.setLanUrl(url(lan));
    await auth.setLanUrl('');

    expect(service.route.value, url(public));
    expect(
        (await StorageService().getServerConfig())!.normalizedLanUrl, isNull);
  });

  // RD: renaming a profile matches the active login by server and user alone, so renaming another profile for
  // the same server renames the login in use too, and the two can no longer be told apart.
  test('renaming another profile for the same server leaves the active one',
      () async {
    final home = (await StorageService().getServerConfig())!
        .copyWith(name: 'home', lanUrl: url(lan));
    await auth.saveProfile(home);

    await auth.renameProfile(home, 'cottage');

    expect(auth.config?.name, isNull);
    expect((await StorageService().getServerConfig())!.name, isNull);
    expect((await StorageService().getSavedProfiles()).map((p) => p.name),
        containsAll([null, 'cottage']));
  });
}
