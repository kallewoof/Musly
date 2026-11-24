import 'package:flutter_test/flutter_test.dart';
import 'package:musly/providers/auth_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/startup_queue_adopter.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _Auth extends AuthProvider {
  _Auth() : super(SubsonicService(), StorageService());

  bool signedIn = false;

  @override
  bool get isAuthenticated => signedIn;

  void signIn() {
    signedIn = true;
    notifyListeners();
  }
}

class _Player extends PlayerProvider {
  _Player()
      : super(
            SubsonicService(),
            StorageService(),
            FakeCastService(),
            UpnpService(),
            MuslyAudioHandler(),
            JukeboxService(),
            TranscodingService());

  int adoptions = 0;

  @override
  Future<void> adoptRemoteQueueAtStart() async => adoptions++;
}

void main() {
  initializeTestEnvironment();

  late _Auth auth;
  late _Player player;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    auth = _Auth();
    player = _Player();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() => player.dispose());

  // RD: the adoption runs before sign-in, when the server cannot be asked, and is never retried; or it runs on
  // every auth change, so a later sign-in or reconnect replaces the queue the user is now on.
  test('adopts once, as soon as the app is signed in', () async {
    StartupQueueAdopter(auth, player).start();
    expect(player.adoptions, 0);

    auth.signIn();
    auth.signIn();

    expect(player.adoptions, 1);
  });

  // RD: starting already signed in waits for a change that never comes, so nothing is adopted.
  test('adopts at once when already signed in', () {
    auth.signedIn = true;

    StartupQueueAdopter(auth, player).start();

    expect(player.adoptions, 1);
  });
}
