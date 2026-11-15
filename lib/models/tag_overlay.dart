/// A song's tag edit on the server (navidrome's `unimouseTagOverlay` extension): the fields its user changed. A
/// null field is as the file has it; an empty one is cleared.
class TagOverlay {
  const TagOverlay({
    required this.id,
    this.title,
    this.artist,
    this.composer,
    this.album,
  });

  final String id;
  final String? title;
  final String? artist;
  final String? composer;
  final String? album;

  bool get hasEdit =>
      title != null || artist != null || composer != null || album != null;

  factory TagOverlay.fromJson(Map<String, dynamic> json) => TagOverlay(
        id: json['id'] as String,
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        composer: json['composer'] as String?,
        album: json['album'] as String?,
      );
}
