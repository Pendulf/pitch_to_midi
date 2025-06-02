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
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
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
  
  bool _showMetronomeFlash = false; // Флаг для "мигательного" показа иконки
  final List<DateTime> _tapTimes = [];
  Timer? _metronomeTimer;
  bool _metronomeActive = false;
  final AudioPlayer _metronomePlayer = AudioPlayer();

  int _bpm = 120;

  bool _isPlaying = false;
  String selectedInstrument = 'Пианино';

  final Map<String, String> instrumentFolders = {
    'Пианино': 'piano',
    'Флейта': 'flute',
    'Ксилофон': 'xylophone',
  };

  final Map<int, String> midiToFileName = {
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

  void _handleBpmTap() {
  final now = DateTime.now();
  _tapTimes.add(now);

  // удаляем старые нажатия (более 2 секунд назад)
  _tapTimes.removeWhere((t) => now.difference(t).inMilliseconds > 2000);

  if (_tapTimes.length >= 2) {
    final intervals = <int>[];
    for (int i = 1; i < _tapTimes.length; i++) {
      intervals.add(_tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds);
    }
    final avgMs = intervals.reduce((a, b) => a + b) / intervals.length;
    final bpm = (60000 / avgMs).round().clamp(40, 240);
    setState(() {
      _bpm = bpm;
    });
  }
}


void _toggleMetronome() {
  if (_metronomeActive) {
    _metronomeTimer?.cancel();
    setState(() {
      _metronomeActive = false;
    });
  } else {
    _startMetronome();
  }
}

void _startMetronome() {
    _metronomeTimer?.cancel();

    final interval = Duration(milliseconds: (60000 / _bpm).round());

    _metronomeTimer = Timer.periodic(interval, (timer) {
      // На каждом "тике" показываем иконку
      setState(() {
        _showMetronomeFlash = true;
      });
      // Через 100 мс скрываем иконку (можно скорректировать длительность "мигания")
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _showMetronomeFlash = false;
          });
        }
      });
    });

    setState(() {
      _metronomeActive = true;
    });
  }


  
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  StreamController<Uint8List>? _streamController;
  StreamSubscription<Uint8List>? _streamSubscription;

  final List<MidiNote> _notes = [];
  final List<double> _buffer = [];

  bool _isRecording = false;
  DateTime? _startTime;
  bool _metronomePressed = false;
  static const int totalBars = 50;
  double get secondsPerBeat => 60.0 / _bpm;

  final List<int> _currentBarNotes = [];
  int _currentBarIndex = 0;
  final List<MidiNote> _barNotes = [];

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

  await _startRecording();

  setState(() {
    _startTime = DateTime.now();
  });
}



  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _startTime = DateTime.now();
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

    while (_buffer.length >= 8820) {
      final chunk = _buffer.sublist(0, 8820);
      _buffer.removeRange(0, 4410);

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

        final barIndex = (time ~/ secondsPerBeat).clamp(0, totalBars - 1);

        if (barIndex != _currentBarIndex) {
          if (_currentBarNotes.isNotEmpty) {
            final mostCommonNote = _mostFrequentNote(_currentBarNotes);
            _barNotes.add(MidiNote(
              mostCommonNote,
              _currentBarIndex * secondsPerBeat,
              secondsPerBeat,
            ));
          } else {
            _barNotes.add(MidiNote(
              -1,
              _currentBarIndex * secondsPerBeat,
              secondsPerBeat,
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

    if (_currentBarNotes.isNotEmpty) {
      final mostCommonNote = _mostFrequentNote(_currentBarNotes);
      _barNotes.add(MidiNote(
        mostCommonNote,
        _currentBarIndex * secondsPerBeat,
        secondsPerBeat,
      ));
    }

    setState(() {
  _isRecording = false;
  _currentBarNotes.clear();
  _currentBarIndex = 0;
  _notes.clear();

  // Фильтрация и нормализация времени нот
  final validNotes = _barNotes.where((n) => n.pitch != -1).toList();
  if (validNotes.isNotEmpty) {
    final minStart = validNotes.map((n) => n.start).reduce(min);
    for (var note in validNotes) {
      _notes.add(MidiNote(
        note.pitch,
        note.start - minStart, // нормализация начала
        note.duration,
      ));
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
  setState(() {
    _isPlaying = true;
  });

  final players = <AudioPlayer>[];

  for (final note in _notes) {
    final fileName = midiToFileName[note.pitch];
    if (fileName == null) continue;

    final player = AudioPlayer();
    players.add(player);

    Future.delayed(Duration(milliseconds: (note.start * 1000).round()), () {
      final folder = instrumentFolders[selectedInstrument]!;
      player.play(AssetSource('sounds/$folder/$fileName'));
    });
  }

  final totalDuration = _notes.map((n) => n.start + n.duration).reduce(max);
  await Future.delayed(Duration(milliseconds: (totalDuration * 1000).round()));

  setState(() {
    _isPlaying = false;
  });
}


  @override
  void dispose() {
    _metronomeTimer?.cancel();
    _metronomePlayer.dispose();
    _streamSubscription?.cancel();
    _streamController?.close();
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }
  @override
@override
Widget build(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;
  final pianoRollHeight = screenHeight * 2 / 3;
  final noteHeight = pianoRollHeight / 24;
  final bottomPadding = 100.0; // Примерная высота нижнего блока с кнопками

  return Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.red[700],  // Просто красный фон
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
  color: Colors.grey[900], // <-- Чёрный фон
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
      // Основная иконка: idle / pressed / active (если метроном запущен)
      Image.asset(
        _metronomePressed
            ? 'assets/icons/bpm_pressed.png'
            : (_metronomeActive
                ? 'assets/icons/bpm_active.png'
                : 'assets/icons/bpm_idle.png'),
        width: 65,
        height: 65,
      ),
      // Надпись "BPM" и текущее значение
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
      // Мигающая иконка, показывается на короткое время (_showMetronomeFlash == true)
      if (_showMetronomeFlash)
        Positioned(
          // Здесь можно скорректировать позицию (например, сделать чуть больше размер или сместить):
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
                thickness: 4, // можно подкорректировать толщину    // высота с отступом, можно настроить
                height: 0.1,
              ),
              SizedBox(
                height: pianoRollHeight,
                child: PianoRollWidget(
                  notes: _notes,
                  noteHeight: noteHeight,
                  secondsPerBeat: secondsPerBeat,
                ),
              ),
              const Spacer(),
              Divider(
                color: Colors.black,
                thickness: 4, // можно подкорректировать толщину    // высота с отступом, можно настроить
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
                        onPressed: _isRecording ? _stopRecording : _startRecordingWithCountdown,
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
                          onPressed: (_isRecording || _isPlaying) ? null : _playRecordedNotes,
                          child: const Text('Играть'),
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
    return Center(
      child: Text(
        'Нет нот',
        style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  final pianoRollHeight = widget.noteHeight * (maxNote - minNote + 1);
  final maxTime = widget.notes.map((n) => n.start + n.duration).fold(0.0, max);

  return GestureDetector(
    onTapDown: (details) {
      if (selectedNoteIndex != null) {
        final localPosition = details.localPosition;
        int newPitch = maxNote - (localPosition.dy / widget.noteHeight).floor();
        newPitch = newPitch.clamp(minNote, maxNote);

        setState(() {
          final original = widget.notes[selectedNoteIndex!];
          widget.notes[selectedNoteIndex!] = MidiNote(
            newPitch,
            original.start,
            original.duration,
          );
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
            for (int i = 0; i < widget.notes.length; i++)
              _buildSelectableNote(i),
          ],
        ),
      ),
    ),
  );
}


  Widget _buildSelectableNote(int index) {
    final note = widget.notes[index];
    final left = keyWidth + note.start * pixelsPerSecond;
    final top = (maxNote - note.pitch) * widget.noteHeight;
    final width = note.duration * pixelsPerSecond;

    final isSelected = selectedNoteIndex == index;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: widget.noteHeight,
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedNoteIndex = index;
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
    final backgroundPaint = Paint()..color = Colors.grey[200]!;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    final gridPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = minNote; i <= maxNote; i++) {
      final y = (maxNote - i) * noteHeight;
      canvas.drawLine(Offset(keyWidth, y), Offset(size.width, y), gridPaint);
    }

    final maxTime = size.width / pixelsPerSecond;
    for (double t = 0; t <= maxTime + 1; t += secondsPerBeat) {
      final x = keyWidth + t * pixelsPerSecond;
      final beatNumber = (t / secondsPerBeat).round();
      final isStrongBeat = beatNumber % 4 == 0;
      final paint = Paint()
        ..color = isStrongBeat ? Colors.black : Colors.grey[400]!
        ..strokeWidth = isStrongBeat ? 1.2 : 0.6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final keyPaintWhite = Paint()..color = Colors.white;
    final keyPaintBlack = Paint()..color = Colors.black87;
    for (int i = minNote; i <= maxNote; i++) {
      final isBlack = _isBlackKey(i);
      final y = (maxNote - i) * noteHeight;
      final rect = Rect.fromLTWH(0, y, keyWidth, noteHeight);
      canvas.drawRect(rect, isBlack ? keyPaintBlack : keyPaintWhite);
    }

    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);
  }

  bool _isBlackKey(int midiNote) {
    final mod = midiNote % 12;
    return [1, 3, 6, 8, 10].contains(mod);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

