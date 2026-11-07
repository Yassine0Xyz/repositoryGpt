# Manual Test Checklist

This checklist records device-dependent regressions that cannot be covered reliably by unit or widget tests. Fill in the device, OS version, date, and result as each item is exercised.

## Test environment

- Device / emulator:
- Android / Linux version:
- App commit:
- Date:

## Playback and audio focus

- [ ] Android smoke test: play a local song, pause/resume, then use next and previous.
- [ ] Add two songs to Queue; verify order, play the queued item, and remove an item.
- [ ] Search by a song title and clear the query; verify the library returns.
- [ ] Toggle a song in Favorites and verify it appears/disappears from the Favorites view.
- [ ] Create a playlist, add a song, rename it, reopen it, and verify the song and trimmed name remain.
- [ ] Rename to a name already used by another playlist; verify both playlists remain distinct and intact.
- [ ] Switch the Songs library between List and Grid and confirm both views can start playback.
- [ ] Phone call or alarm interrupts playback and playback resumes only when appropriate.
- [ ] Another music app requests audio focus.
- [ ] Headphones / Bluetooth device disconnect while playing.
- [ ] Bluetooth media buttons control playback and queue navigation.
- [ ] Background playback and notification controls work after locking the screen.

## Persistence and library

- [ ] Swipe the app away from Recents; playback and app state behave as expected.
- [ ] Low-memory process kill and restore.
- [ ] Large library (target: 5,000 songs) loads and scrolls without blocking the UI.
- [ ] A deleted file in a saved queue is skipped safely.
- [ ] Media permission denied, then granted in system Settings.
- [ ] On Android 13+ and Android 12 or lower, deny audio permission, grant it from system Settings while YAZEN remains in memory, then resume and refresh; verify the library appears without force-stopping.
- [ ] Revoke audio permission from system Settings while YAZEN is in memory; resume or refresh and verify stale audio rows disappear and the recovery actions are shown.
- [ ] Open two folders with the same basename under different parents; verify distinct labels, exact track counts, and no cross-folder tracks.
- [ ] Open a folder from the loaded library; verify exact full-path matching, including nested folders and separator normalization, without a new full-library query or tracks from sibling/prefix folders.
- [ ] Add or remove a media file, refresh the library, and verify Folder results reflect the refreshed contents and removed folders return no tracks.
- [ ] Rename a custom playlist; cancel once, try a whitespace-only name, then save a trimmed name and verify it appears immediately and after reopening/restarting YAZEN.
- [ ] Rename a playlist to another playlist's existing name and verify both playlists retain their own IDs and contents; if saving fails, verify the old name remains visible and persisted.
- [ ] Switch Songs between List and Grid and between Comfortable and Compact density; verify preferences persist after restart and selection/playback actions still work in both layouts.
- [ ] Replace or update a song at the same path and refresh; verify its displayed size and modification date update.
- [ ] With a saved queue containing missing files, verify the first app frame appears promptly, missing entries are pruned, and the selected track/position is correct.
- [ ] Play a track repeatedly and verify the active library view does not visibly rebuild or jump its scroll position.
- [ ] Rapidly select tracks and add, remove, reorder, skip, and clear queue items; verify the displayed queue and playing track stay aligned.
- [ ] Set Equalizer enabled state, preset, band gains, and surround; restart the app and start playback to verify they are restored after a new audio session is created.

## Accessibility, motion, and layout

- [ ] Arabic / RTL layout.
- [ ] 200% text scale without clipped controls or overflow.
- [ ] Reduced motion enabled.
- [ ] Performance mode (not implemented in the current source; add this check after a user-facing setting exists).

## Video and timers

- [ ] Picture-in-Picture entry and return.
- [ ] Video screen-on behavior while playing, and release on pause/background/dispose.
- [ ] Sleep timer: duration, end-of-current-track, end-of-queue, cancellation, and fade-out.
- [ ] Sleep timer: cancel or replace during fade restores the user volume.
- [ ] Sleep timer: Stop cancels the timer and restores volume.
- [ ] Sleep timer: queue boundary does not advance after end-of-current-track.

## Round 2 device checks

- [ ] R8 release-build smoke test: local playback, notification controls, visualizer, video thumbnails, and library query.
- [ ] Video PiP: keep-screen-on remains active while video is playing in PiP, and releases after pause/exit.
- [ ] End-of-current-track timer pauses before the next item with repeat-one enabled.
- [ ] Visualizer progress line remains smooth between position events and avoids rebuilding unrelated player content.
- [ ] Ambient Color Flow: quiet/loud audio, pause/resume, missing artwork, theme contrast, and track palette transition.
- [ ] Ambient Color Flow: rotate the device; run a ten-minute memory/frame-rate check; verify thermal and battery impact.
- [ ] Turn Ambient Color Flow off in Settings during playback; confirm it disappears immediately and stops its ticker/PCM consumer. Turn it back on and confirm it returns without reopening the player.
- [ ] Cover the full player with another route, background the app, then return; confirm Ambient Color Flow pauses and resumes without stale energy state.
- [ ] Enable system reduced motion; confirm Ambient Color Flow remains visible and static and lyric transitions respect the setting.
- [ ] Toggle dynamic artwork colors on and off while playing; verify the 800 ms track transition, theme fallback for missing/gray artwork, and readable seek/lyric labels in light and dark themes.
- [ ] Scrub seek while synced lyrics are open; verify time preview and active lyric follow remain smooth and do not cause unrelated screen rebuilds.

## Library scroll performance regression checks

- [ ] 500+ songs: fast repeated flings in Songs List with cold and warm artwork cache.
- [ ] 500+ songs: fast repeated flings in Songs Grid with cold and warm artwork cache.
- [ ] Reverse direction quickly during a fling; verify artwork for the final visible rows loads.
- [ ] Stop during a fling; verify visible rows do not remain stuck on placeholders.
- [ ] Include songs with missing artwork and unusually large embedded artwork.
- [ ] On older Android versions, verify embedded artwork is downsampled and the media retriever/file handles are released after success and failure.
- [ ] Verify play, favorite, add-to-playlist, and long-press selection actions remain functional after row-button simplification.
- [ ] Compare UI-thread and raster-thread frame charts on the same device before and after the artwork changes.

## Results / notes

| Date | Device / OS | Scenario | Result | Notes |
|---|---|---|---|---|
