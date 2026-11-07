import 'dart:convert';
import 'dart:io';

/// A timestamped lyric entry extracted from an ID3 SYLT frame.
class EmbeddedId3LyricLine {
  const EmbeddedId3LyricLine({required this.timestampMs, required this.text});

  final int timestampMs;
  final String text;
}

/// Lyrics found directly inside an audio file's ID3v2 tag.
class EmbeddedId3Lyrics {
  const EmbeddedId3Lyrics({
    this.unsynced,
    this.synchronized = const <EmbeddedId3LyricLine>[],
    this.warnings = const <String>[],
  });

  final String? unsynced;
  final List<EmbeddedId3LyricLine> synchronized;
  final List<String> warnings;

  bool get isEmpty =>
      (unsynced == null || unsynced!.trim().isEmpty) && synchronized.isEmpty;
}

/// Read-only ID3v2 parser for embedded USLT and SYLT lyrics.
///
/// The parser only reads the ID3v2 block at the beginning of an MP3 and does
/// not decode or execute any media content. It supports ID3v2.3 and v2.4.
class EmbeddedId3LyricsReader {
  const EmbeddedId3LyricsReader();

  // Lyrics tags should be small. Refuse pathological/corrupt tags before
  // allocating a large buffer from an untrusted local file.
  static const _maxTagSizeBytes = 8 * 1024 * 1024;

  Future<EmbeddedId3Lyrics?> read(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final header = await handle.read(10);
      if (header.length < 10 ||
          header[0] != 0x49 ||
          header[1] != 0x44 ||
          header[2] != 0x33) {
        return null;
      }

      final majorVersion = header[3];
      if (majorVersion != 3 && majorVersion != 4) return null;
      final flags = header[5];
      final tagSize = _synchsafe(header.sublist(6, 10));
      if (tagSize <= 0) return null;
      if (tagSize > _maxTagSizeBytes) {
        return const EmbeddedId3Lyrics(
          warnings: <String>['The ID3 tag is larger than the safe limit.'],
        );
      }

      final tagData = await handle.read(tagSize);
      if (tagData.length != tagSize) {
        return const EmbeddedId3Lyrics(
          warnings: <String>['The ID3 tag is truncated.'],
        );
      }

      var offset = 0;
      final warnings = <String>[];
      // ID3v2 extended headers are included in the tag size.
      if ((flags & 0x40) != 0 && tagData.length >= 4) {
        final extendedSize =
            majorVersion == 3
                ? _uint32(tagData, 0)
                : _synchsafe(tagData.sublist(0, 4));
        final skip = majorVersion == 3 ? extendedSize + 4 : extendedSize;
        if (skip <= tagData.length) {
          offset = skip;
        } else {
          warnings.add('The ID3 extended header is invalid.');
          return EmbeddedId3Lyrics(warnings: warnings);
        }
      }

      String? unsynced;
      final synced = <EmbeddedId3LyricLine>[];
      while (offset + 10 <= tagData.length) {
        final frameId = ascii.decode(
          tagData.sublist(offset, offset + 4),
          allowInvalid: true,
        );
        if (frameId.codeUnits.every(
          (value) => value == 0x00 || value == 0x20,
        )) {
          break;
        }
        final frameSize =
            majorVersion == 4
                ? _synchsafe(tagData.sublist(offset + 4, offset + 8))
                : _uint32(tagData, offset + 4);
        if (frameSize <= 0 || offset + 10 + frameSize > tagData.length) {
          warnings.add('An ID3 frame was truncated or invalid.');
          break;
        }
        final body = tagData.sublist(offset + 10, offset + 10 + frameSize);
        try {
          if (frameId == 'USLT' && unsynced == null) {
            final parsed = _parseUslt(body);
            if (parsed != null && parsed.trim().isNotEmpty) {
              unsynced = parsed.trim();
            }
          } else if (frameId == 'SYLT') {
            final parsed = _parseSylt(body, warnings);
            synced.addAll(parsed);
          }
        } catch (_) {
          warnings.add('Could not parse ID3 frame $frameId.');
        }
        offset += 10 + frameSize;
      }

      synced.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      return EmbeddedId3Lyrics(
        unsynced: unsynced,
        synchronized: List<EmbeddedId3LyricLine>.unmodifiable(synced),
        warnings: List<String>.unmodifiable(warnings),
      );
    } on IOException {
      return null;
    } finally {
      await handle?.close();
    }
  }

  String? _parseUslt(List<int> body) {
    if (body.length < 4) return null;
    final encoding = body[0];
    // USLT: encoding byte, 3-byte language, description, then text.
    final descriptionStart = 4;
    final separator = _findTerminator(body, descriptionStart, encoding);
    if (separator < 0) return null;
    final textStart = separator + _terminatorLength(encoding);
    return _decode(body.sublist(textStart), encoding);
  }

  List<EmbeddedId3LyricLine> _parseSylt(List<int> body, List<String> warnings) {
    if (body.length < 6) return const <EmbeddedId3LyricLine>[];
    final encoding = body[0];
    // SYLT: encoding, language(3), timestamp format, content type,
    // description, then repeated (terminated text, uint32 timestamp).
    final timestampFormat = body[4];
    if (timestampFormat != 1) {
      warnings.add(
        'SYLT uses MPEG-frame timestamps; only millisecond SYLT is supported.',
      );
      return const <EmbeddedId3LyricLine>[];
    }
    final descriptionSeparator = _findTerminator(body, 6, encoding);
    if (descriptionSeparator < 0) return const <EmbeddedId3LyricLine>[];
    var offset = descriptionSeparator + _terminatorLength(encoding);
    final result = <EmbeddedId3LyricLine>[];
    while (offset < body.length) {
      final textSeparator = _findTerminator(body, offset, encoding);
      if (textSeparator < 0 ||
          textSeparator + _terminatorLength(encoding) + 4 > body.length) {
        break;
      }
      final text =
          _decode(body.sublist(offset, textSeparator), encoding).trim();
      offset = textSeparator + _terminatorLength(encoding);
      final timestamp = _uint32(body, offset);
      offset += 4;
      if (text.isNotEmpty) {
        result.add(EmbeddedId3LyricLine(timestampMs: timestamp, text: text));
      }
    }
    return result;
  }

  int _findTerminator(List<int> bytes, int start, int encoding) {
    final width = _terminatorLength(encoding);
    for (var index = start; index + width <= bytes.length; index++) {
      if (width == 1 && bytes[index] == 0) return index;
      if (width == 2 && bytes[index] == 0 && bytes[index + 1] == 0) {
        return index;
      }
    }
    return -1;
  }

  int _terminatorLength(int encoding) => encoding == 1 || encoding == 2 ? 2 : 1;

  String _decode(List<int> bytes, int encoding) {
    if (bytes.isEmpty) return '';
    switch (encoding) {
      case 0:
        return latin1.decode(bytes, allowInvalid: true);
      case 1:
        return _decodeUtf16(bytes, littleEndian: _hasUtf16LeBom(bytes));
      case 2:
        return _decodeUtf16(bytes, littleEndian: false);
      case 3:
        return utf8.decode(bytes, allowMalformed: true);
      default:
        return latin1.decode(bytes, allowInvalid: true);
    }
  }

  String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    var data = bytes;
    if (data.length >= 2 &&
        ((data[0] == 0xff && data[1] == 0xfe) ||
            (data[0] == 0xfe && data[1] == 0xff))) {
      littleEndian = data[0] == 0xff;
      data = data.sublist(2);
    }
    final units = <int>[];
    for (var index = 0; index + 1 < data.length; index += 2) {
      units.add(
        littleEndian
            ? data[index] | (data[index + 1] << 8)
            : (data[index] << 8) | data[index + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  bool _hasUtf16LeBom(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe;

  int _uint32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  int _synchsafe(List<int> bytes) =>
      (bytes[0] << 21) | (bytes[1] << 14) | (bytes[2] << 7) | bytes[3];
}
