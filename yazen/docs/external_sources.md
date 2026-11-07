# External implementation sources

The following facts were verified from public sources during implementation.

- Demucs current PyPI release: 4.1.0, requires Python >=3.10, MIT license, and produces the four standard stems vocals, bass, drums, and other. Source: https://pypi.org/project/demucs/
- Official Demucs repository documents the htdemucs model, four-stem output, CLI usage, and Python invocation through `demucs.separate.main`. Source: https://github.com/facebookresearch/demucs
- `just_audio` 0.10.6 exposes the experimental `LockCachingAudioSource`, which streams while writing to a local cache file and provides a download-progress stream. Source: https://pub.dev/packages/just_audio
- `just_audio` 0.10.6 exposes AndroidEqualizer, AudioPipeline, AndroidEqualizerParameters, and AndroidEqualizerBand runtime APIs. Source: https://pub.dev/packages/just_audio
- on_audio_query 2.9.0 ArtistModel exposes `artist`, `numberOfAlbums`, and `numberOfTracks`; AlbumModel exposes `album`, `artist`, and `numOfSongs`. Sources: https://pub.dev/documentation/on_audio_query/latest/on_audio_query/ArtistModel-class.html and https://pub.dev/documentation/on_audio_query/latest/on_audio_query/AlbumModel-class.html
- LRCLIB documents a free no-registration lyrics API and syncedLyrics/plainLyrics response fields. Source: https://lrclib.net/docs

- pusher_channels_flutter 2.6.0 documents `PusherChannelsFlutter.getInstance()`, `init`, `subscribe`, `connect`, presence channels, member callbacks, and client event triggering. It supports Android, iOS, and web. Source: https://pub.dev/packages/pusher_channels_flutter
- nsd 5.0.1 documents `startDiscovery`, `stopDiscovery`, `register`, `unregister`, `Service`, `Discovery`, `Registration`, and the Android/iOS local-network permissions. Source: https://pub.dev/packages/nsd
- Pusher client events require private or presence channel authorization and the `client-` event prefix. Source: https://pusher.com/docs/channels/using_channels/events/
