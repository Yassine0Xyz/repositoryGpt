import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Real local-file spectrum source for Linux desktop.
///
/// ffmpeg decodes the selected file to mono 32-bit float PCM. The service
/// computes FFT frames from those samples and exposes them by track position.
/// It intentionally has no timer/sine/random fallback: until decoded frames
/// exist, callers receive `preparing` or `unavailable`.
class LinuxPcmSpectrumService {
  LinuxPcmSpectrumService._();

  static final LinuxPcmSpectrumService instance = LinuxPcmSpectrumService._();

  static const int _sampleRate = 44100;
  static const int _fftSize = 2048;
  static const int _hopSamples = 1764; // 40 ms at 44.1 kHz.
  static const int _bandCount = 40;
  static const int _maxFrames = 60000;
  static const double _minFrequency = 35.0;
  static const double _maxFrequency = 20000.0;

  Process? _process;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  final List<List<double>> _frames = <List<double>>[];
  List<double> _sampleWindow = <double>[];
  String? _sourcePath;
  String _state = 'idle';
  int _generation = 0;
  int _totalFrames = 0;

  bool get isActive => _state == 'preparing' || _state == 'ready';

  Future<bool> start(String sourceUri) async {
    await stop();
    final generation = ++_generation;

    final path = _pathFromUri(sourceUri);
    if (path == null || !File(path).existsSync()) {
      _state = 'unavailable';
      return false;
    }

    _sourcePath = path;
    _state = 'preparing';
    _sampleWindow = <double>[];
    _frames.clear();
    _totalFrames = 0;
    _pending.clear();

    try {
      final process = await Process.start('ffmpeg', <String>[
        '-v',
        'error',
        '-i',
        path,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '$_sampleRate',
        '-f',
        'f32le',
        'pipe:1',
      ], runInShell: false);
      if (generation != _generation || _sourcePath != path) {
        process.kill(ProcessSignal.sigterm);
        return false;
      }
      _process = process;
      _stdoutSubscription = process.stdout.listen(
        (chunk) {
          if (generation == _generation) _consume(chunk);
        },
        onError: (_) {
          if (generation == _generation && _frames.isEmpty) {
            _state = 'unavailable';
          }
        },
        onDone: () {
          if (generation == _generation && _frames.isEmpty) {
            _state = 'unavailable';
          }
        },
        cancelOnError: false,
      );
      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen((_) {});
      unawaited(
        process.exitCode.then((_) {
          if (generation == _generation && _frames.isEmpty) {
            _state = 'unavailable';
          }
        }),
      );
      return true;
    } on ProcessException {
      _state = 'unavailable';
      return false;
    } catch (_) {
      _state = 'unavailable';
      return false;
    }
  }

  Map<String, Object> read(int positionMs) {
    if (_frames.isEmpty) {
      return <String, Object>{
        'state': _state == 'unavailable' ? 'unavailable' : 'preparing',
      };
    }
    final requestedFrame = (positionMs / 40).floor();
    if (requestedFrame >= _maxFrames && _totalFrames >= _maxFrames) {
      return <String, Object>{'state': 'unavailable'};
    }
    final frameIndex = requestedFrame.clamp(0, _frames.length - 1);
    _state = 'ready';
    return <String, Object>{'state': 'live', 'bands': _frames[frameIndex]};
  }

  Future<void> stop() async {
    ++_generation;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(milliseconds: 250));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
    }
    _pending.clear();
    _sampleWindow = <double>[];
    _frames.clear();
    _totalFrames = 0;
    _sourcePath = null;
    _state = 'idle';
  }

  void _consume(List<int> chunk) {
    _pending.add(chunk);
    final bytes = _pending.takeBytes();
    final usableBytes = bytes.length - (bytes.length % 4);
    if (usableBytes <= 0) {
      _pending.add(bytes);
      return;
    }
    if (usableBytes < bytes.length) {
      _pending.add(bytes.sublist(usableBytes));
    }
    final data = ByteData.sublistView(
      Uint8List.sublistView(bytes, 0, usableBytes),
    );
    for (var offset = 0; offset < usableBytes; offset += 4) {
      _sampleWindow.add(data.getFloat32(offset, Endian.little));
    }
    while (_sampleWindow.length >= _fftSize) {
      _totalFrames++;
      if (_frames.length < _maxFrames) {
        _frames.add(_analyzeFrame(_sampleWindow));
      }
      if (_sampleWindow.length < _hopSamples) {
        _sampleWindow = <double>[];
      } else {
        _sampleWindow = _sampleWindow.sublist(_hopSamples);
      }
      if (_state == 'preparing') _state = 'ready';
    }
  }

  List<double> _analyzeFrame(List<double> samples) {
    final real = List<double>.filled(_fftSize, 0.0);
    final imaginary = List<double>.filled(_fftSize, 0.0);
    for (var i = 0; i < _fftSize; i++) {
      final hann = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (_fftSize - 1)));
      real[i] = samples[i] * hann;
    }
    _fft(real, imaginary);

    final magnitudes = List<double>.filled(_fftSize ~/ 2, 0.0);
    for (var i = 1; i < magnitudes.length; i++) {
      magnitudes[i] = math.sqrt(
        real[i] * real[i] + imaginary[i] * imaginary[i],
      );
    }
    final bands = List<double>.filled(_bandCount, 0.0);
    final maxFrequency = math.min(_maxFrequency, _sampleRate / 2.0);
    for (var band = 0; band < _bandCount; band++) {
      final startFrequency =
          _minFrequency *
          math.pow(maxFrequency / _minFrequency, band / _bandCount);
      final endFrequency =
          _minFrequency *
          math.pow(maxFrequency / _minFrequency, (band + 1) / _bandCount);
      final startBin = math.max(
        1,
        (startFrequency * _fftSize / _sampleRate).floor(),
      );
      final endBin = math.min(
        magnitudes.length - 1,
        math.max(startBin + 1, (endFrequency * _fftSize / _sampleRate).ceil()),
      );
      var sum = 0.0;
      var peak = 0.0;
      for (var bin = startBin; bin <= endBin; bin++) {
        sum += magnitudes[bin] * magnitudes[bin];
        peak = math.max(peak, magnitudes[bin]);
      }
      final count = math.max(1, endBin - startBin + 1);
      final rms = math.sqrt(sum / count) / 170.0;
      final normalized = math.pow(
        (rms * 1.35 + peak / 260.0).clamp(0.0, 1.0),
        0.62,
      );
      bands[band] = normalized.toDouble().clamp(0.0, 1.0);
    }
    return bands;
  }

  void _fft(List<double> real, List<double> imaginary) {
    final n = real.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final realValue = real[i];
        real[i] = real[j];
        real[j] = realValue;
        final imaginaryValue = imaginary[i];
        imaginary[i] = imaginary[j];
        imaginary[j] = imaginaryValue;
      }
    }
    for (var length = 2; length <= n; length <<= 1) {
      final angle = -2.0 * math.pi / length;
      final wLengthReal = math.cos(angle);
      final wLengthImaginary = math.sin(angle);
      for (var start = 0; start < n; start += length) {
        var wReal = 1.0;
        var wImaginary = 0.0;
        final half = length >> 1;
        for (var i = 0; i < half; i++) {
          final even = start + i;
          final odd = even + half;
          final oddReal = real[odd] * wReal - imaginary[odd] * wImaginary;
          final oddImaginary = real[odd] * wImaginary + imaginary[odd] * wReal;
          real[odd] = real[even] - oddReal;
          imaginary[odd] = imaginary[even] - oddImaginary;
          real[even] += oddReal;
          imaginary[even] += oddImaginary;
          final nextWReal = wReal * wLengthReal - wImaginary * wLengthImaginary;
          wImaginary = wReal * wLengthImaginary + wImaginary * wLengthReal;
          wReal = nextWReal;
        }
      }
    }
  }

  String? _pathFromUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.scheme == 'file') return uri.toFilePath();
    if (uri.scheme.isEmpty) return value;
    return null;
  }
}
