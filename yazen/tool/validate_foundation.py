from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
required = [
    ROOT / 'pubspec.yaml',
    ROOT / 'README.md',
    ROOT / 'analysis_options.yaml',
    ROOT / 'lib/main.dart',
    ROOT / 'lib/models/media_track.dart',
    ROOT / 'lib/core/theme/theme_provider.dart',
    ROOT / 'lib/core/theme/theme_tokens.dart',
    ROOT / 'lib/services/hybrid_audio_handler.dart',
    ROOT / 'lib/services/media_library_service.dart',
    ROOT / 'lib/services/local_playlist_manager.dart',
    ROOT / 'lib/services/media_track_codec.dart',
    ROOT / 'lib/services/playback_state_store.dart',
    ROOT / 'lib/services/lyrics_service.dart',
    ROOT / 'lib/controllers/hybrid_music_controller.dart',
    ROOT / 'lib/screens/home/home_screen.dart',
    ROOT / 'lib/screens/player/full_player_screen.dart',
    ROOT / 'lib/screens/library/local_media_screen.dart',
    ROOT / 'lib/screens/settings/settings_screen.dart',
    ROOT / 'lib/screens/queue/queue_screen.dart',
    ROOT / 'lib/screens/collections/favorites_screen.dart',
    ROOT / 'lib/screens/collections/playlist_details_screen.dart',
    ROOT / 'test/playback_state_store_test.dart',
    ROOT / 'test/local_playlist_manager_test.dart',
    ROOT / 'lib/widgets/shimmer_skeleton.dart',
    ROOT / 'lib/widgets/alive_effects.dart',
    ROOT / 'lib/widgets/audio_visualizer.dart',
    ROOT / 'lib/widgets/theme_picker_sheet.dart',
    ROOT / 'lib/screens/effects/equalizer_screen.dart',
    ROOT / 'lib/screens/home/widgets/library_tabs.dart',
    ROOT / 'lib/screens/home/widgets/track_list_tile.dart',
    ROOT / 'lib/widgets/mini_player.dart',
    ROOT / 'lib/widgets/lyrics_view.dart',
    ROOT / 'lib/widgets/playlist_picker_sheet.dart',
    ROOT / 'android/app/src/main/res/raw/keep.xml',
    ROOT / 'android/app/src/main/AndroidManifest.xml',
    ROOT / 'android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt',
    ROOT / 'android/app/src/main/res/values/styles.xml',
]

for path in required:
    assert path.exists(), f'Missing required file: {path}'

pubspec = (ROOT / 'pubspec.yaml').read_text()
for dependency in ('just_audio:', 'audio_service:', 'on_audio_query:', 'provider:', 'http:', 'shared_preferences:', 'video_player:'):

    assert dependency in pubspec, f'Missing dependency: {dependency}'

for dart_file in (ROOT / 'lib').rglob('*.dart'):
    source = dart_file.read_text()
    for imported in re.findall(r"import '([^']+)';", source):
        if imported.startswith('../') or imported.startswith('./'):
            target = (dart_file.parent / imported).resolve()
            assert target.exists(), f'Broken import {imported} in {dart_file}'

print('Foundation validation passed.')
