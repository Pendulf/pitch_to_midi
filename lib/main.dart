import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomePage(),
      theme: ThemeData(primarySwatch: Colors.blue),
    );
  }
}

class MidiNote {
  final int pitch;
  final double start;
  final double duration;

  MidiNote(this.pitch, this.start, this.duration);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  StreamController<Uint8List>? _streamController;
  StreamSubscription<Uint8List>? _streamSubscription;

  final List<MidiNote> _notes = [];
  final List<double> _buffer = [];

  bool _isRecording = false;
  DateTime? _startTime;

  static const int totalBars = 8;
  static const double barDuration = 1.0; // 1 секунда на такт

  List<int> _currentBarNotes = [];
  int _currentBarIndex = 0;
  final List<MidiNote> _barNotes = [];

  Timer? _metronomeTimer;

  @override
  void initState() {
    super.initState();
    _openRecorder();
    _player.openPlayer();
  }

  Future<void> _openRecorder() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _recorder.openRecorder();
  }

  Future<void> _startRecordingWithCountdown() async {
    setState(() {
      _isRecording = false;
      _notes.clear();
      _buffer.clear();
      _barNotes.clear();
      _currentBarNotes.clear();
      _currentBarIndex = 0;
      _startTime = null;
    });

    // 4 тикания по 0.5 секунды (тик-така тик-така)
    int tickCount = 0;
    const int maxTicks = 4;
    const durationBetweenTicks = Duration(milliseconds: 500);

    _metronomeTimer?.cancel();

    _metronomeTimer = Timer.periodic(durationBetweenTicks, (timer) async {
      if (tickCount >= maxTicks) {
        timer.cancel();
        await _startRecording();
        return;
      }
      await _playClick();
      tickCount++;
    });
  }

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _startTime = DateTime.now();
    });

    // После старта записи метроном больше не играет
    _metronomeTimer?.cancel();

    _streamController = StreamController<Uint8List>();
    _streamSubscription = _streamController!.stream.listen((buffer) {
      _processAudio(buffer);
    });

    await _recorder.startRecorder(
      toStream: _streamController!.sink,
      codec: Codec.pcm16,
      sampleRate: 44100,
      numChannels: 1,
    );
  }

  Future<void> _playClick() async {
    const freq = 1000.0; // частота клика 1кГц
    const durationMs = 100;
    final sampleRate = 44100;
    final samplesCount = (sampleRate * durationMs / 1000).round();

    final buffer = Float64List(samplesCount);
    for (int i = 0; i < samplesCount; i++) {
      buffer[i] = sin(2 * pi * freq * i / sampleRate);
    }

    final pcmData = Int16List(samplesCount);
    for (int i = 0; i < samplesCount; i++) {
      pcmData[i] = (buffer[i] * 32767).toInt();
    }

    await _player.startPlayer(
      fromDataBuffer: Uint8List.view(pcmData.buffer),
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: 1,
      whenFinished: () {},
    );
  }

  void _processAudio(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    for (int i = 0; i < byteData.lengthInBytes; i += 2) {
      final int sample = byteData.getInt16(i, Endian.little);
      _buffer.add(sample / 32768.0);
    }

    while (_buffer.length >= 2048) {
      final chunk = _buffer.sublist(0, 2048);
      _buffer.removeRange(0, 1024);

      double sumSquares = 0;
      for (var sample in chunk) {
        sumSquares += sample * sample;
      }
      final rms = sqrt(sumSquares / chunk.length);

      const double volumeThreshold = 0.02;
      if (rms < volumeThreshold) {
        continue;
      }

      final freq = _detectPitch(chunk, 44100);
      if (freq != null) {
        final midi = _frequencyToMidi(freq);
        final now = DateTime.now();
        final time = now.difference(_startTime!).inMilliseconds / 1000.0;

        final barIndex = (time ~/ barDuration).clamp(0, totalBars - 1);

        if (barIndex != _currentBarIndex) {
          if (_currentBarNotes.isNotEmpty) {
            final mostCommonNote = _mostFrequentNote(_currentBarNotes);
            _barNotes.add(MidiNote(
              mostCommonNote,
              _currentBarIndex * barDuration,
              barDuration,
            ));
          } else {
            _barNotes.add(MidiNote(
              -1,
              _currentBarIndex * barDuration,
              barDuration,
            ));
          }
          _currentBarNotes.clear();
          _currentBarIndex = barIndex;
        }

        _currentBarNotes.add(midi);
        setState(() {});
      }
    }
  }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();

    await _streamSubscription?.cancel();
    await _streamController?.close();
    _streamSubscription = null;
    _streamController = null;

    _metronomeTimer?.cancel();

    if (_currentBarNotes.isNotEmpty) {
      final mostCommonNote = _mostFrequentNote(_currentBarNotes);
      _barNotes.add(MidiNote(
        mostCommonNote,
        _currentBarIndex * barDuration,
        barDuration,
      ));
    }

    setState(() {
      _isRecording = false;
      _currentBarNotes.clear();
      _currentBarIndex = 0;
      _notes.clear();
      for (var barNote in _barNotes) {
        if (barNote.pitch != -1) {
          _notes.add(barNote);
        }
      }
      _barNotes.clear();
    });
  }

  int _mostFrequentNote(List<int> notes) {
    final freqMap = <int, int>{};
    for (var note in notes) {
      freqMap[note] = (freqMap[note] ?? 0) + 1;
    }
    int maxCount = 0;
    int mostCommon = notes[0];
    freqMap.forEach((note, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommon = note;
      }
    });
    return mostCommon;
  }

  double? _detectPitch(List<double> samples, int sampleRate) {
    int size = samples.length;
    int maxLag = min(1000, size ~/ 2);
    double bestCorr = 0.0;
    int bestLag = 0;

    for (int lag = 50; lag < maxLag; lag++) {
      double corr = 0.0;
      for (int i = 0; i < size - lag; i++) {
        corr += samples[i] * samples[i + lag];
      }
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }
    if (bestLag == 0) return null;

    final freq = sampleRate / bestLag;
    if (freq < 50 || freq > 1000) return null;
    return freq;
  }

  int _frequencyToMidi(double freq) {
    return (69 + 12 * (log(freq / 440) / ln2)).round();
  }

  // --- Добавлено: Воспроизведение записанных нот ---

  Future<void> _playRecordedNotes() async {
    if (_notes.isEmpty) return;

    for (var note in _notes) {
      final freq = _frequencyFromMidi(note.pitch);
      if (freq == null) continue;

      await _playTone(freq, (note.duration * 1000).toInt());
      await Future.delayed(const Duration(milliseconds: 50)); // интервал между нотами
    }
  }

  double? _frequencyFromMidi(int midiNote) {
    if (midiNote < 21 || midiNote > 108) return null;
    return 440.0 * pow(2, (midiNote - 69) / 12);
  }

  Future<void> _playTone(double freq, int durationMs) async {
    const sampleRate = 44100;
    final samplesCount = (sampleRate * durationMs / 1000).round();

    final buffer = Float64List(samplesCount);
    for (int i = 0; i < samplesCount; i++) {
      buffer[i] = sin(2 * pi * freq * i / sampleRate);
    }

    final pcmData = Int16List(samplesCount);
    for (int i = 0; i < samplesCount; i++) {
      pcmData[i] = (buffer[i] * 32767).toInt();
    }

    await _player.startPlayer(
      fromDataBuffer: Uint8List.view(pcmData.buffer),
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: 1,
      whenFinished: () {},
    );

    // Ждём окончания проигрывания
    await Future.delayed(Duration(milliseconds: durationMs));
  }

  @override
  void dispose() {
    _metronomeTimer?.cancel();
    _streamSubscription?.cancel();
    _streamController?.close();
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice to MIDI (с отсчетом)')),
      body: Column(
        children: [
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isRecording ? _stopRecording : _startRecordingWithCountdown,
            child: Text(_isRecording ? 'Остановить запись' : 'Начать запись с отсчетом'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isRecording ? null : _playRecordedNotes,
            child: const Text('Воспроизвести записанные ноты'),
          ),
          const SizedBox(height: 20),
          Expanded(child: PianoRollWidget(notes: _notes)),
        ],
      ),
    );
  }
}

class PianoRollWidget extends StatelessWidget {
  final List<MidiNote> notes;
  const PianoRollWidget({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    return notes.isEmpty
        ? const Center(child: Text('Нет нот'))
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CustomPaint(
              size: const Size(1200, 900),
              painter: PianoRollPainter(notes),
            ),
          );
  }
}

class PianoRollPainter extends CustomPainter {
  final List<MidiNote> notes;
  final double pixelsPerSecond = 100;
  final double noteHeight = 10;

  PianoRollPainter(this.notes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blueAccent;

    for (final note in notes) {
      final left = note.start * pixelsPerSecond;
      final width = note.duration * pixelsPerSecond;
      final top = size.height - (note.pitch - 21) * noteHeight;
      canvas.drawRect(Rect.fromLTWH(left, top, width, noteHeight), paint);
    }

    final keyPaintWhite = Paint()..color = Colors.white;
    final keyPaintBlack = Paint()..color = Colors.black87;

    for (int i = 21; i <= 108; i++) {
      final isBlack = _isBlackKey(i);
      final y = size.height - (i - 21) * noteHeight;
      final rect = Rect.fromLTWH(0, y, 30, noteHeight);
      canvas.drawRect(rect, isBlack ? keyPaintBlack : keyPaintWhite);
    }
  }

  bool _isBlackKey(int midiNote) {
    final mod = midiNote % 12;
    return [1, 3, 6, 8, 10].contains(mod);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
