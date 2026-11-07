import 'package:path/path.dart' as p;

import '../models/media_track.dart';

/// Normalizes a media folder path for stable identity and exact lookup.
///
/// MediaStore paths are POSIX paths even when tests or imported metadata use
/// backslashes, so normalize with the POSIX path context on every platform.
String normalizeFolderIdentity(String path) {
  final value = path.trim().replaceAll(r'\', '/');
  if (value.isEmpty) return '';
  return p.posix.normalize(value);
}

/// Returns a compact label that distinguishes equal basenames in different
/// parent folders while retaining the basename as the primary label.
String folderDisplayName(String path) {
  final identity = normalizeFolderIdentity(path);
  if (identity.isEmpty) return path;
  const storageRoots = <String>[
    '/storage/emulated/0/',
    '/storage/self/primary/',
    '/sdcard/',
  ];
  for (final root in storageRoots) {
    if (identity.startsWith(root)) {
      final relative = identity.substring(root.length);
      return relative.split('/').where((part) => part.isNotEmpty).join(' · ');
    }
  }
  final relative = identity.startsWith('/') ? identity.substring(1) : identity;
  final parts = relative.split('/').where((part) => part.isNotEmpty);
  return parts.isEmpty ? p.posix.basename(identity) : parts.join(' · ');
}

/// Returns stable, unique full-path folder identities from local tracks.
List<String> folderIdentities(Iterable<MediaTrack> tracks) {
  final identities = <String>{};
  for (final track in tracks) {
    final folder = track.folder;
    if (folder == null) continue;
    final identity = normalizeFolderIdentity(folder);
    if (identity.isNotEmpty) identities.add(identity);
  }
  final result = identities.toList(growable: false)..sort((a, b) {
    final byLabel = folderDisplayName(
      a,
    ).toLowerCase().compareTo(folderDisplayName(b).toLowerCase());
    return byLabel == 0 ? a.compareTo(b) : byLabel;
  });
  return List<String>.unmodifiable(result);
}

/// Returns only tracks in the requested folder, using the same normalized
/// full-path identity that is used to build the folder list.
List<MediaTrack> tracksInFolder(Iterable<MediaTrack> tracks, String folder) {
  final target = normalizeFolderIdentity(folder);
  if (target.isEmpty) return const <MediaTrack>[];
  final matchingTracks = <MediaTrack>[];
  for (final track in tracks) {
    final path = track.folder;
    if (path != null && normalizeFolderIdentity(path) == target) {
      matchingTracks.add(track);
    }
  }
  return List<MediaTrack>.unmodifiable(matchingTracks);
}
