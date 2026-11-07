/// Sorting choices exposed by the local library UI.
enum LibrarySort {
  newestFirst,
  oldestFirst,
  sizeLowToHigh,
  sizeHighToLow,
  durationShortToLong,
  durationLongToShort,
  nameAZ,
  nameZA,
  artistAZ,
  mostPlayed,
  recentlyPlayedFirst,
}

/// Filters supported by the local audio/video library.
enum LibraryFilter { all, favorites, importedFiles, missingAlbum }
