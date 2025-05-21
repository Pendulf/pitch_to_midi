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

  StreamController<Uint8List>? _streamController;
  StreamSubscription<Uint8List>? _streamSubscription;

  final List<MidiNote> _notes = [];
  final List<double> _buffer = [];

  bool _isRecording = false;
  DateTime? _startTime;
  int? _currentNote;
  double? _noteStartTime;

  @override
  void initState() {
    super.initState();
    _openRecorder();
  }

  Future<void> _openRecorder() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _recorder.openRecorder();
  }

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _notes.clear();
      _buffer.clear();
      _startTime = DateTime.now();
      _currentNote = null;
      _noteStartTime = null;
    });

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

  void _processAudio(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    for (int i = 0; i < byteData.lengthInBytes; i += 2) {
      final int sample = byteData.getInt16(i, Endian.little);
      _buffer.add(sample / 32768.0);
    }

    while (_buffer.length >= 2048) {
      final chunk = _buffer.sublist(0, 2048);
      _buffer.removeRange(0, 1024);

      final freq = _detectPitch(chunk, 44100);
      if (freq != null) {
        final midi = _frequencyToMidi(freq);
        final now = DateTime.now();
        final time = now.difference(_startTime!).inMilliseconds / 1000.0;

        if (_currentNote == null || _currentNote != midi) {
          if (_currentNote != null && _noteStartTime != null) {
            _notes.add(MidiNote(_currentNote!, _noteStartTime!, time - _noteStartTime!));
          }
          _currentNote = midi;
          _noteStartTime = time;
          setState(() {});
        }
      }
    }
  }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();

    await _streamSubscription?.cancel();
    await _streamController?.close();
    _streamSubscription = null;
    _streamController = null;

    setState(() {
      _isRecording = false;
      if (_currentNote != null && _noteStartTime != null && _startTime != null) {
        final totalTime = DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;
        _notes.add(MidiNote(_currentNote!, _noteStartTime!, totalTime - _noteStartTime!));
        _currentNote = null;
        _noteStartTime = null;
      }
    });
  }

  // Автокорреляция для pitch detection
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

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _streamController?.close();
    _recorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice to MIDI (flutter_sound)')),
      body: Column(
        children: [
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isRecording ? _stopRecording : _startRecording,
            child: Text(_isRecording ? 'Остановить запись' : 'Начать запись'),
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
              size: const Size(2000, 900),
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
