import 'dart:io';
import 'dart:typed_data';

import 'package:yazen/services/embedded_id3_lyrics.dart';

List<int> syncSafe(int value) => [
  (value >> 21) & 0x7f,
  (value >> 14) & 0x7f,
  (value >> 7) & 0x7f,
  value & 0x7f,
];

List<int> uint32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

List<int> frame(String id, List<int> body) => [
  ...id.codeUnits,
  ...uint32(body.length),
  0,
  0,
  ...body,
];

void main() async {
  final uslt = [3, 101, 110, 103, 0, ...'Embedded lyric'.codeUnits];
  final sylt = [
    3,
    101,
    110,
    103,
    1,
    1,
    0,
    ...'sync'.codeUnits,
    0,
    ...'Hello'.codeUnits,
    0,
    ...uint32(1250),
  ];
  final frames = [...frame('USLT', uslt), ...frame('SYLT', sylt)];
  final bytes = Uint8List.fromList([
    0x49, 0x44, 0x33, 0x03, 0x00, 0x00,
    ...syncSafe(frames.length),
    ...frames,
    // Fake MPEG bytes are unnecessary; the reader only consumes the ID3 block.
  ]);
  final file = File('/tmp/yazen-id3-test.mp3');
  await file.writeAsBytes(bytes);
  final result = await const EmbeddedId3LyricsReader().read(file.path);
  assert(result != null);
  final parsed = result!;
  assert(parsed.unsynced == 'Embedded lyric');
  assert(parsed.synchronized.length == 1);
  assert(parsed.synchronized.single.timestampMs == 1250);
  assert(parsed.synchronized.single.text == 'Hello');
  await file.delete();
  stdout.writeln('embedded_id3_uslt_sylt_ok');
}
