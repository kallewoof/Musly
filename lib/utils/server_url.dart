/// A server address as typed, with the scheme added when it was left out: https for the server's address,
/// http for its address on the local network, where a server rarely has a certificate.
String withScheme(String typed, {required bool lan}) {
  final url = typed.trim();
  if (url.isEmpty || url.contains('://')) return url;
  return '${lan ? 'http' : 'https'}://$url';
}
