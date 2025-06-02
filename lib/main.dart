import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

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
  static const int totalBars = 40;
  static const Map<int, String> midiToFileName = {
    48: 'c4.wav',
    49: 'cs4.wav',
    50: 'd4.wav',
    51: 'ds4.wav',
    52: 'e4.wav',
    53: 'f4.wav',
    54: 'fs4.wav',
    55: 'g4.wav',
    56: 'gs4.wav',
    57: 'a4.wav',
    58: 'as4.wav',
    59: 'b4.wav',
    60: 'c5.wav',
    61: 'cs5.wav',
    62: 'd5.wav',
    63: 'ds5.wav',
    64: 'e5.wav',
    65: 'f5.wav',
    66: 'fs5.wav',
    67: 'g5.wav',
    68: 'gs5.wav',
    69: 'a5.wav',
    70: 'as5.wav',
    71: 'b5.wav',
  };
  static const Map<String, String> instrumentFolders = {
    'Пианино': 'piano',
    'Флейта': 'flute',
    'Ксилофон': 'xylophone',
  };

  bool _showMetronomeFlash = false;
  bool _metronomeActive = false;
  bool _metronomePressed = false;
  int _bpm = 120;
  final List<DateTime> _tapTimes = [];
  Timer? _metronomeTimer;

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamController<Uint8List>? _streamController;
  StreamSubscription<Uint8List>? _streamSubscription;
  bool _isRecording = false;
  DateTime? _startTime;

  final List<MidiNote> _notes = [];
  final List<double> _buffer = [];
  final List<int> _currentBarNotes = [];
  int _currentBarIndex = 0;
  final List<MidiNote> _barNotes = [];

  final List<AudioPlayer> _playbackPlayers = [];
  bool _isPlaying = false;

  String selectedInstrument = 'Пианино';

  double get secondsPerBeat => 60.0 / _bpm;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _player.openPlayer();
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _recorder.openRecorder();
  }

  void _toggleMetronome() {
    if (_metronomeActive) {
      _metronomeTimer?.cancel();
      setState(() {
        _metronomeActive = false;
        _showMetronomeFlash = false;
      });
    } else {
      _startMetronome();
    }
  }

  void _startMetronome() {
    _metronomeTimer?.cancel();
    final interval = Duration(milliseconds: (60000 / _bpm).round());
    _metronomeTimer = Timer.periodic(interval, (_) {
      setState(() => _showMetronomeFlash = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showMetronomeFlash = false);
      });
    });
    setState(() => _metronomeActive = true);
  }

  void _handleBpmTap() {
    final now = DateTime.now();
    _tapTimes.add(now);
    _tapTimes.removeWhere((t) => now.difference(t).inMilliseconds > 2000);
    if (_tapTimes.length < 2) return;

    final intervals = [
      for (int i = 1; i < _tapTimes.length; i++)
        _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds
    ];
    final avgMs = intervals.reduce((a, b) => a + b) / intervals.length;
    final newBpm = (60000 / avgMs).round().clamp(40, 240);
    setState(() => _bpm = newBpm);
    if (_metronomeActive) _startMetronome();
  }

  void _onStopButtonPressed() => _stopRecording();

  Future<void> _startRecordingWithCountdown() async {
    if (_isPlaying) _stopPlayback();
    setState(() {
      _isRecording = false;
      _notes.clear();
      _buffer.clear();
      _barNotes.clear();
      _currentBarNotes.clear();
      _currentBarIndex = 0;
      _startTime = null;
    });
    await _startRecording();
    setState(() => _startTime = DateTime.now());
  }

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _startTime = DateTime.now();
    });
    _streamController = StreamController<Uint8List>();
    _streamSubscription = _streamController!.stream.listen(_processAudio);
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
      _buffer.add(byteData.getInt16(i, Endian.little) / 32768.0);
    }
    while (_buffer.length >= 8820) {
      final chunk = _buffer.sublist(0, 8820);
      _buffer.removeRange(0, 4410);
      final rms = sqrt(chunk.fold<double>(0, (sum, x) => sum + x * x) / chunk.length);
      if (rms < 0.02) continue;

      final freq = _detectPitch(chunk, 44100);
      if (freq == null) continue;
      final midi = _frequencyToMidi(freq);
      final now = DateTime.now();
      final time = now.difference(_startTime!).inMilliseconds / 1000.0;
      final maxDuration = totalBars * secondsPerBeat;
      if (time >= maxDuration && _isRecording) {
        _onStopButtonPressed();
        return;
      }
      final barIndex = (time ~/ secondsPerBeat).clamp(0, totalBars - 1);
      if (barIndex != _currentBarIndex) {
        final noteToAdd = _currentBarNotes.isNotEmpty
            ? _mostFrequentNote(_currentBarNotes)
            : -1;
        _barNotes.add(MidiNote(noteToAdd, _currentBarIndex * secondsPerBeat, secondsPerBeat));
        _currentBarNotes.clear();
        _currentBarIndex = barIndex;
      }
      _currentBarNotes.add(midi);
      setState(() {});
    }
  }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    await _streamSubscription?.cancel();
    await _streamController?.close();
    _streamSubscription = null;
    _streamController = null;

    if (_currentBarNotes.isNotEmpty) {
      final mostCommon = _mostFrequentNote(_currentBarNotes);
      _barNotes.add(MidiNote(mostCommon, _currentBarIndex * secondsPerBeat, secondsPerBeat));
    }

    setState(() {
      _isRecording = false;
      _currentBarNotes.clear();
      _currentBarIndex = 0;
      _notes.clear();

      final valid = _barNotes.where((n) => n.pitch != -1).toList();
      if (valid.isNotEmpty) {
        final minStart = valid.map((n) => n.start).reduce(min);
        for (var n in valid) {
          _notes.add(MidiNote(n.pitch, n.start - minStart, n.duration));
        }
      }
      _barNotes.clear();
    });
  }

  int _mostFrequentNote(List<int> notes) {
    final freqMap = <int, int>{};
    for (var n in notes) {
      freqMap[n] = (freqMap[n] ?? 0) + 1;
    }
    return freqMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  double? _detectPitch(List<double> samples, int sr) {
    final size = samples.length;
    final maxLag = min(1000, size ~/ 2);
    double bestCorr = 0;
    int bestLag = 0;
    for (var lag = 50; lag < maxLag; lag++) {
      var corr = 0.0;
      for (var i = 0; i < size - lag; i++) {
        corr += samples[i] * samples[i + lag];
      }
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }
    if (bestLag == 0) return null;
    final freq = sr / bestLag;
    return (freq < 50 || freq > 1000) ? null : freq;
  }

  int _frequencyToMidi(double freq) => (69 + 12 * (log(freq / 440) / ln2)).round();

  void _stopPlayback() {
    for (var p in _playbackPlayers) {
      p.stop();
    }
    _playbackPlayers.clear();
    setState(() => _isPlaying = false);
  }

  Future<void> _playRecordedNotes() async {
    setState(() => _isPlaying = true);
    _playbackPlayers.clear();
    for (var note in _notes) {
      final fileName = midiToFileName[note.pitch];
      if (fileName == null) continue;
      final player = AudioPlayer();
      _playbackPlayers.add(player);
      Future.delayed(Duration(milliseconds: (note.start * 1000).round()), () {
        if (_isPlaying) {
          final folder = instrumentFolders[selectedInstrument]!;
          player.play(AssetSource('sounds/$folder/$fileName'));
        }
      });
    }
    final totalDuration = _notes.map((n) => n.start + n.duration).reduce(max);
    await Future.delayed(Duration(milliseconds: (totalDuration * 1000).round()));
    if (_isPlaying) setState(() => _isPlaying = false);
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
  final screenHeight = MediaQuery.of(context).size.height;
  final pianoRollHeight = screenHeight * 2 / 3;
  final noteHeight = pianoRollHeight / 24;
  final bottomPadding = 100.0;

  final bool noNotesRecognized = _notes.isEmpty;
  final bool allBelowFourthOctave = _notes.isNotEmpty && _notes.every((n) => n.pitch < 48);

  return Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.red[700],
      title: Text(
        selectedInstrument,
        style: TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(2),
        child: Container(
          color: Colors.black,
          height: 4,
        ),
      ),
    ),
    body: Container(
      color: Colors.grey[800],
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomPadding - 10,
            child: Container(
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              Container(
                color: Colors.grey[900],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: instrumentFolders.keys.map((instrument) {
                        final isActive = selectedInstrument == instrument;
                        final folderName = instrumentFolders[instrument];
                        return IconButton(
                          iconSize: 40,
                          onPressed: () {
                            setState(() {
                              selectedInstrument = instrument;
                            });
                          },
                          icon: Image.asset(
                            'assets/icons/$folderName${isActive ? "active" : "inactive"}.png',
                            width: 65,
                            height: 65,
                          ),
                          tooltip: instrument,
                        );
                      }).toList(),
                    ),
                    const SizedBox(width: 15),
                    GestureDetector(
                      onTap: _handleBpmTap,
                      onLongPress: _toggleMetronome,
                      onTapDown: (_) => setState(() => _metronomePressed = true),
                      onTapUp: (_) => setState(() => _metronomePressed = false),
                      onTapCancel: () => setState(() => _metronomePressed = false),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            _metronomePressed
                                ? 'assets/icons/bpm_pressed.png'
                                : (_metronomeActive
                                    ? 'assets/icons/bpm_active.png'
                                    : 'assets/icons/bpm_idle.png'),
                            width: 65,
                            height: 65,
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'BPM',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                                ),
                              ),
                              Text(
                                '$_bpm',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                                ),
                              ),
                            ],
                          ),
                          if (_showMetronomeFlash)
                            Positioned(
                              child: Image.asset(
                                'assets/icons/bpm_active.png',
                                width: 65,
                                height: 65,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                color: Colors.black,
                thickness: 4,
                height: 0.1,
              ),
              SizedBox(
                height: pianoRollHeight,
                child: () {
                  if (noNotesRecognized) {
                    return const Center(
                      child: Text(
                        'Ноты не распознаны        Попробуйте ещё раз',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  } else if (allBelowFourthOctave) {
                    return const Center(
                      child: Text(
                        'Ноты ниже 3-ей октавы        Пойте выше',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  } else {
                    return PianoRollWidget(
                      notes: _notes,
                      noteHeight: noteHeight,
                      secondsPerBeat: secondsPerBeat,
                    );
                  }
                }(),
              ),
              const Spacer(),
              Divider(
                color: Colors.black,
                thickness: 4,
                height: 0.1,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[800],
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 3),
                          minimumSize: const Size.fromHeight(65),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                          ),
                        ),
                        onPressed: _isRecording
                            ? _onStopButtonPressed
                            : _startRecordingWithCountdown,
                        child: Text(_isRecording ? 'Стоп' : 'Запись'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (_notes.isNotEmpty)
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[800],
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white, width: 3),
                            minimumSize: const Size.fromHeight(65),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 26,
                            ),
                          ),
                          onPressed: _isRecording
                              ? null
                              : (_isPlaying ? _stopPlayback : _playRecordedNotes),
                          child: Text(_isPlaying ? 'Сброс' : 'Играть'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}

class PianoRollWidget extends StatefulWidget {
  final List<MidiNote> notes;
  final double noteHeight;
  final double secondsPerBeat;
  const PianoRollWidget({
    super.key,
    required this.notes,
    required this.noteHeight,
    required this.secondsPerBeat,
  });

  @override
  State<PianoRollWidget> createState() => _PianoRollWidgetState();
}

class _PianoRollWidgetState extends State<PianoRollWidget> {
  static const int minNote = 48;
  static const int maxNote = 71;
  static const double keyWidth = 30;
  static const double pixelsPerSecond = 200;

  int? selectedNoteIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.notes.isEmpty) {
      return const Center(
        child: Text(
          'Нет нот',
          style: TextStyle(
            fontSize: 24,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final pianoRollHeight = widget.noteHeight * (maxNote - minNote + 1);
    final maxTime = widget.notes.map((n) => n.start + n.duration).fold(0.0, max);

    return GestureDetector(
      onTapDown: (details) {
        if (selectedNoteIndex != null) {
          final localY = details.localPosition.dy;
          int newPitch = maxNote - (localY / widget.noteHeight).floor();
          newPitch = newPitch.clamp(minNote, maxNote);
          setState(() {
            final orig = widget.notes[selectedNoteIndex!];
            widget.notes[selectedNoteIndex!] =
                MidiNote(newPitch, orig.start, orig.duration);
            selectedNoteIndex = null;
          });
        }
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: keyWidth + maxTime * pixelsPerSecond + 200,
          height: pianoRollHeight,
          child: Stack(
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: PianoRollGridPainter(
                  noteHeight: widget.noteHeight,
                  secondsPerBeat: widget.secondsPerBeat,
                ),
              ),
              for (var i = 0; i < widget.notes.length; i++) _noteTile(i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteTile(int index) {
    final n = widget.notes[index];
    final left = keyWidth + n.start * pixelsPerSecond;
    final top = (maxNote - n.pitch) * widget.noteHeight;
    final width = n.duration * pixelsPerSecond;
    final isSelected = selectedNoteIndex == index;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: widget.noteHeight,
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedNoteIndex = (selectedNoteIndex == index) ? null : index;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.green : Colors.red,
            border: Border.all(color: Colors.black, width: 1),
          ),
        ),
      ),
    );
  }
}

class PianoRollGridPainter extends CustomPainter {
  final double noteHeight;
  final double secondsPerBeat;
  static const double pixelsPerSecond = 200;
  static const int minNote = 48;
  static const int maxNote = 71;
  static const double keyWidth = 30;

  PianoRollGridPainter({
    required this.noteHeight,
    required this.secondsPerBeat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.grey[200]!;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    final grid = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = minNote; i <= maxNote; i++) {
      final y = (maxNote - i) * noteHeight;
      canvas.drawLine(Offset(keyWidth, y), Offset(size.width, y), grid);
    }

    final maxTime = size.width / pixelsPerSecond;
    for (var t = 0.0; t <= maxTime + 1; t += secondsPerBeat) {
      final x = keyWidth + t * pixelsPerSecond;
      final beat = (t / secondsPerBeat).round();
      final strong = beat % 4 == 0;
      final linePaint = Paint()
        ..color = strong ? Colors.black : Colors.grey[400]!
        ..strokeWidth = strong ? 1.2 : 0.6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    final white = Paint()..color = Colors.white;
    final black = Paint()..color = Colors.black87;
    for (var i = minNote; i <= maxNote; i++) {
      final isBlackKey = [1, 3, 6, 8, 10].contains(i % 12);
      final y = (maxNote - i) * noteHeight;
      canvas.drawRect(Rect.fromLTWH(0, y, keyWidth, noteHeight), isBlackKey ? black : white);
    }

    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
