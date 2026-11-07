import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/library_display_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads and persists library layout and density', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'yazen.library.layout': 'grid',
      'yazen.library.density': 'compact',
    });

    final settings = LibraryDisplaySettings.instance;
    await settings.load();

    expect(settings.layoutMode, LibraryLayoutMode.grid);
    expect(settings.density, LibraryDensity.compact);

    await settings.setLayoutMode(LibraryLayoutMode.list);
    await settings.setDensity(LibraryDensity.comfortable);
    await settings.setVideosLayoutMode(LibraryLayoutMode.grid);
    await settings.setVideosDensity(LibraryDensity.compact);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('yazen.library.layout'), 'list');
    expect(preferences.getString('yazen.library.density'), 'comfortable');
    expect(settings.videosLayoutMode, LibraryLayoutMode.grid);
    expect(settings.videosDensity, LibraryDensity.compact);
    expect(preferences.getString('yazen.library.videos.layout'), 'grid');
    expect(preferences.getString('yazen.library.videos.density'), 'compact');
  });
}
