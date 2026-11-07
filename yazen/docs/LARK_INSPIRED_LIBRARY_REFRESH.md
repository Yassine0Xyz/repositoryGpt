# Lark-inspired library refresh improvements

## Source observations from the supplied decompiled Lark APK

- `MediaDatabaseHelper$updateByPage$2` performs updates in bounded page-sized
  transaction batches. This is a database-write strategy, not proof that Lark's
  visible song list is loaded through UI pagination.
- `MediaFileObserverHelper$doOnEvent$1` guards overlapping observer work and
  dispatches a scan after file events. The decompiled snippet shows a scan
  trigger and a simple in-flight guard; it does not establish all debounce or
  scheduling behavior of the full application.

## YAZEN adaptation

YAZEN currently queries the Android MediaStore catalog through
`on_audio_query`, then builds an immutable `LibraryIndexSnapshot`. Its song
list is already virtualized with builder-backed list/grid widgets, and its
scroll/artwork paths already use viewport coalescing and bounded image loading.
A superficial UI pagination rewrite would not reduce the initial MediaStore
query or retained catalog, so it was deliberately not introduced.

This iteration instead improves refresh publication:

1. A refresh keeps the current immutable library visible while the replacement
   MediaStore result is being read; it no longer switches the whole screen into
   the initial-load spinner state.
2. If a refresh is requested during the initial library load, one follow-up
   refresh is queued instead of silently discarded.
3. Each library load receives a generation. A slower, older query cannot
   overwrite a newer snapshot after a later scan has started.
4. A failed background refresh leaves the last good library snapshot in place
   and reports the error, rather than replacing the list with an empty state.

## Deliberately not copied

No Lark proprietary source code was transplanted. No Lark database schema,
scanner, native service, or media observer implementation was copied. YAZEN
continues to use its existing MediaStore provider and Flutter architecture.

## Verification boundary

A focused regression test was added for keeping the old list visible while a
refresh query is pending. The local environment does not contain Flutter or
Dart executables, so `dart format`, `flutter analyze`, `flutter test`, and an
APK build could not be run. The change is source-level and still needs runtime
verification on the target Android device.
