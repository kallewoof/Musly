import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// How this install names itself to the server.
///
/// The client name (Subsonic `c`) is per install, not per app: the server records it as the play queue's
/// `changedBy`, which is how a device tells its own saved queue from one another device left behind.
class ClientIdentity {
  const ClientIdentity({required this.clientName, required this.userAgent});

  factory ClientIdentity.forInstall({
    required String installId,
    required String version,
    String? platform,
  }) {
    final os = platform ?? currentPlatform();
    return ClientIdentity(
      clientName: 'Musly-$os-$installId',
      userAgent: 'Musly/$version ($os)',
    );
  }

  static const anonymous = ClientIdentity(
    clientName: 'Musly',
    userAgent: 'Musly',
  );

  final String clientName;
  final String userAgent;

  static String currentPlatform() => kIsWeb ? 'web' : Platform.operatingSystem;
}
