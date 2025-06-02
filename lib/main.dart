import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

// Точка входа приложения
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Фиксируем портретную ориентацию экрана
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

// Основной виджет приложения
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomePage(), // Стартовая страница
    );
  }
}

// Класс для хранения данных о MIDI-ноте
class MidiNote {
  final int pitch;       // Высота ноты в MIDI-формате
  final double start;    // Время начала ноты (в секундах)
  final double duration; // Длительность ноты (в секундах)

  MidiNote(this.pitch, this.start, this.duration);
}

// Главная страница с реализацией записи, метронома и проигрывания
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Количество тактов, на которые рассчитана запись
  static const int totalBars = 40;

  // Словарь: MIDI-номер ноты -> название файла звука
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

  // Словарь: название инструмента -> папка с его звуками
  static const Map<String, String> instrumentFolders = {
    'Пианино': 'piano',
    'Флейта': 'flute',
    'Ксилофон': 'xylophone',
  };

  // Параметры метронома
  bool _showMetronomeFlash = false; // Мигание метронома
  bool _metronomeActive = false;    // Активен ли метроном
  bool _metronomePressed = false;   // Состояние нажатия на кнопку метронома
  int _bpm = 120;                   // Темп (ударов в минуту)
  final List<DateTime> _tapTimes = []; // Список времён нажатий для определения BPM по тапу
  Timer? _metronomeTimer;              // Таймер для метронома

  // Объекты для записи и воспроизведения аудио
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamController<Uint8List>? _streamController;        // Поток сырых аудиоданных
  StreamSubscription<Uint8List>? _streamSubscription;     // Подписка на обработку аудио
  bool _isRecording = false;                             // Флаг записи
  DateTime? _startTime;                                  // Время начала записи

  // Буфер для промежуточной обработки аудио
  final List<double> _buffer = [];
  // Список MIDI-нотов, распознанных за текущий такт
  final List<int> _currentBarNotes = [];
  int _currentBarIndex = 0;      // Индекс текущего такта при записи
  final List<MidiNote> _barNotes = [];   // Список самых частых нот по тактам

  // Итоговые распознанные ноты, готовые для воспроизведения
  final List<MidiNote> _notes = [];
  // Проигрыватели для параллельного воспроизведения нот
  final List<AudioPlayer> _playbackPlayers = [];
  bool _isPlaying = false;       // Флаг воспроизведения

  String selectedInstrument = 'Пианино'; // Выбранный инструмент пользователя

  // Вычисляем длительность одного удара (в секундах)
  double get secondsPerBeat => 60.0 / _bpm;

  @override
  void initState() {
    super.initState();
    _initRecorder();    // Запрос разрешений и инициализация рекордера
  }

  // Инициализация рекордера: запрашиваем права на микрофон
  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _recorder.openRecorder();
  }

  // Переключение состояния метронома (вкл/выкл)
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

  // Запуск метронома: установка периодического таймера
  void _startMetronome() {
    _metronomeTimer?.cancel();
    final interval = Duration(milliseconds: (60000 / _bpm).round());
    _metronomeTimer = Timer.periodic(interval, (_) {
      // При каждом тике включение иконки на 100 миллисекунд
      setState(() => _showMetronomeFlash = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showMetronomeFlash = false);
      });
    });
    setState(() => _metronomeActive = true);
  }

  // Обработка тапов для определения нового BPM
  void _handleBpmTap() {
    final now = DateTime.now();
    _tapTimes.add(now);
    // Удаляем слишком старые тапы более чем 2 секунды назад
    _tapTimes.removeWhere((t) => now.difference(t).inMilliseconds > 2000);
    if (_tapTimes.length < 2) return;

    // Вычисляем интервалы между тапами и средний интервал
    final intervals = [
      for (int i = 1; i < _tapTimes.length; i++)
        _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds
    ];
    final avgMs = intervals.reduce((a, b) => a + b) / intervals.length;
    final newBpm = (60000 / avgMs).round().clamp(40, 240);
    setState(() => _bpm = newBpm);
    // Если метроном активен, перезапускаем с новым темпом
    if (_metronomeActive) _startMetronome();
  }

  // Обработчик нажатия кнопки "Стоп" при записи
  void _onStopButtonPressed() => _stopRecording();

  // Запуск записи с обнулением предыдущих данных
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

  // Функция старта записи аудио
  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _startTime = DateTime.now();
    });
    // Создаем контроллер потока для получения PCM-данных
    _streamController = StreamController<Uint8List>();
    _streamSubscription = _streamController!.stream.listen(_processAudio);
    await _recorder.startRecorder(
      toStream: _streamController!.sink,
      codec: Codec.pcm16,
      sampleRate: 44100,
      numChannels: 1,
    );
  }

  // Обработка поступающих кусочков аудиоданных
  void _processAudio(Uint8List buffer) {
    // Преобразуем Uint8List в список double значений PCM (-1.0..1.0)
    final byteData = ByteData.sublistView(buffer);
    for (int i = 0; i < byteData.lengthInBytes; i += 2) {
      _buffer.add(byteData.getInt16(i, Endian.little) / 32768.0);
    }
    // Как только накопили достаточно данных (8820 сэмплов ≈ 0.2 сек)
    while (_buffer.length >= 8820) {
      final chunk = _buffer.sublist(0, 8820);
      // Сдвигаем окно на половину (4410), чтобы перекрытие было 50%
      _buffer.removeRange(0, 4410);
      // Вычисляем RMS (корень из среднего квадрата) для определения тишины
      final rms = sqrt(chunk.fold<double>(0, (sum, x) => sum + x * x) / chunk.length);
      if (rms < 0.02) continue; // Пропускаем тихие участки

      // Пытаемся детектировать частоту ноты
      final freq = _detectPitch(chunk, 44100);
      if (freq == null) continue;
      final midi = _frequencyToMidi(freq);

      final now = DateTime.now();
      final time = now.difference(_startTime!).inMilliseconds / 1000.0;
      final maxDuration = totalBars * secondsPerBeat;
      // Если превышен максимум по времени, останавливаем запись
      if (time >= maxDuration && _isRecording) {
        _onStopButtonPressed();
        return;
      }
      // Вычисляем индекс текущего такта
      final barIndex = (time ~/ secondsPerBeat).clamp(0, totalBars - 1);
      // Если перешли в новый такт, сохраняем наиболее частую ноту из предыдущего
      if (barIndex != _currentBarIndex) {
        final noteToAdd = _currentBarNotes.isNotEmpty
            ? _mostFrequentNote(_currentBarNotes)
            : -1;
        _barNotes.add(MidiNote(
          noteToAdd,
          _currentBarIndex * secondsPerBeat,
          secondsPerBeat,
        ));
        _currentBarNotes.clear();
        _currentBarIndex = barIndex;
      }
      // Сохраняем детектированную ноту в текущий такт
      _currentBarNotes.add(midi);
      setState(() {}); // Обновляем интерфейс (например, прогресс)
    }
  }

  // Остановка записи и финальная обработка накопленных данных
  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    await _streamSubscription?.cancel();
    await _streamController?.close();
    _streamSubscription = null;
    _streamController = null;

    // Сохраняем данные последнего такта, если что-то есть
    if (_currentBarNotes.isNotEmpty) {
      final mostCommon = _mostFrequentNote(_currentBarNotes);
      _barNotes.add(MidiNote(
        mostCommon,
        _currentBarIndex * secondsPerBeat,
        secondsPerBeat,
      ));
    }

    setState(() {
      _isRecording = false;
      _currentBarNotes.clear();
      _currentBarIndex = 0;
      _notes.clear();

      // Фильтруем ноты с валидным pitch (не -1), выравниваем по минимальному старту
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

  // Возвращает наиболее частую ноту из списка
  int _mostFrequentNote(List<int> notes) {
    final freqMap = <int, int>{};
    for (var n in notes) {
      freqMap[n] = (freqMap[n] ?? 0) + 1;
    }
    return freqMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  // Алгоритм автокорреляции для обнаружения частоты ноты
  double? _detectPitch(List<double> samples, int sr) {
    final size = samples.length;
    final maxLag = min(1000, size ~/ 2);
    double bestCorr = 0;
    int bestLag = 0;
    // Проходим по возможным лагам (50..maxLag)
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
    // Игнорируем нерелевантные частоты (<50 Гц или >1000 Гц)
    return (freq < 50 || freq > 1000) ? null : freq;
  }

  // Преобразование частоты в MIDI-номер ноты
  int _frequencyToMidi(double freq) =>
      (69 + 12 * (log(freq / 440) / ln2)).round();

  // Остановка воспроизведения всех активных плееров
  void _stopPlayback() {
    for (var p in _playbackPlayers) {
      p.stop();
    }
    _playbackPlayers.clear();
    setState(() => _isPlaying = false);
  }

  // Проигрывание распознанных нот в хронологическом порядке
  Future<void> _playRecordedNotes() async {
    setState(() => _isPlaying = true);
    _playbackPlayers.clear();
    for (var note in _notes) {
      final fileName = midiToFileName[note.pitch];
      if (fileName == null) continue;
      final player = AudioPlayer();
      _playbackPlayers.add(player);
      // Запускаем каждый звук в момент note.start
      Future.delayed(Duration(milliseconds: (note.start * 1000).round()), () {
        if (_isPlaying) {
          final folder = instrumentFolders[selectedInstrument]!;
          player.play(AssetSource('sounds/$folder/$fileName'));
        }
      });
    }
    // Вычисляем общую длительность очереди нот
    final totalDuration =
        _notes.map((n) => n.start + n.duration).reduce(max);
    // Ждем, пока все ноты не исполнятся
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
    // Высота области Piano Roll (две трети экрана)
    final pianoRollHeight = screenHeight * 2 / 3;
    // Высота одной ноты (разбиваем по 24 полутонов)
    final noteHeight = pianoRollHeight / 24;
    final bottomPadding = 100.0;

    // Флаги для отображения сообщений вместо PianoRoll
    final bool noNotesRecognized = _notes.isEmpty;
    final bool allBelowFourthOctave =
        _notes.isNotEmpty && _notes.every((n) => n.pitch < 48);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red[700],
        centerTitle: true,
        title: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(width: 200),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 13), 
                child: Image.asset( 
                  'assets/image/logo.png',
                  height: 25,
                ),
              ),
            ),
            Center(
              child: Text(
                selectedInstrument,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
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
                // Панель выбора инструмента и метронома
                Container(
                  color: Colors.grey[900],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Иконки переключения инструментов
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
                              // Выбираем активную или неактивную иконку
                              'assets/icons/$folderName${isActive ? "active" : "inactive"}.png',
                              width: 65,
                              height: 65,
                            ),
                            tooltip: instrument,
                          );
                        }).toList(),
                      ),
                      const SizedBox(width: 15),
                      // Кнопка TAP/метроном
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
                              // Смена иконки в зависимости от состояния
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
                                  '$_bpm', // Текущий темп
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
                                // Отображение мигающего метронома
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
                // Область Piano Roll
                SizedBox(
                  height: pianoRollHeight,
                  child: () {
                    if (noNotesRecognized) {
                      // Если ноты не распознаны, выводим сообщение
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
                      // Если все ноты ниже 3-й октавы, предупреждаем
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
                      // Иначе рисуем виджет Piano Roll
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
                // Кнопки управления записью и воспроизведением
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
                          // Если идёт запись, кнопка "Стоп", иначе "Запись"
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
                            // Кнопка воспроизведения/сброса нот
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

// Виджет для отображения Piano Roll с нотами
class PianoRollWidget extends StatefulWidget {
  final List<MidiNote> notes;         // Список распознанных нот
  final double noteHeight;            // Высота одного "тонового" ряда
  final double secondsPerBeat;        // Длина одного удара (сек)

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
  // Ограничения по полутонам для показа (от C4 до B5)
  static const int minNote = 48;
  static const int maxNote = 71;
  static const double keyWidth = 30;              // Ширина клавиш в левой части
  static const double pixelsPerSecond = 200;      // Масштаб по горизонтали

  int? selectedNoteIndex; // Индекс выбранной ноты для перемещения

  @override
  Widget build(BuildContext context) {

    // Полная высота сетки для всех нот
    final pianoRollHeight = widget.noteHeight * (maxNote - minNote + 1);
    // Максимальное время по всем нотам
    final maxTime = widget.notes.map((n) => n.start + n.duration).fold(0.0, max);

    return GestureDetector(
      // Обработка тапов для перемещения выбранной ноты по вертикали
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
          // Ширина сетки зависит от длительности нот
          width: keyWidth + maxTime * pixelsPerSecond + 200,
          height: pianoRollHeight,
          child: Stack(
            children: [
              // Фон и сетка
              CustomPaint(
                size: Size.infinite,
                painter: PianoRollGridPainter(
                  noteHeight: widget.noteHeight,
                  secondsPerBeat: widget.secondsPerBeat,
                ),
              ),
              // Отрисовка каждой ноты
              for (var i = 0; i < widget.notes.length; i++) _noteTile(i),
            ],
          ),
        ),
      ),
    );
  }

  // Создает виджет прямоугольника для одной ноты
  Widget _noteTile(int index) {
    final n = widget.notes[index];
    // Позиционируем по горизонтали (start * масштаб)
    final left = keyWidth + n.start * pixelsPerSecond;
    // Позиционируем по вертикали (инвертированная нота)
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

// Кастомный рисовальщик сетки и клавиатуры слева
class PianoRollGridPainter extends CustomPainter {
  final double noteHeight;      // Высота одного ряда
  final double secondsPerBeat;  // Длительность удара (сек)
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
    // Рисуем фон канваса
    final bg = Paint()..color = Colors.grey[200]!;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    // Рисуем горизонтальные линии сетки (каждый полутон)
    final grid = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = minNote; i <= maxNote; i++) {
      final y = (maxNote - i) * noteHeight;
      canvas.drawLine(Offset(keyWidth, y), Offset(size.width, y), grid);
    }

    // Рисуем вертикальные линии (каждый удар)
    final maxTime = size.width / pixelsPerSecond;
    for (var t = 0.0; t <= maxTime + 1; t += secondsPerBeat) {
      final x = keyWidth + t * pixelsPerSecond;
      final beat = (t / secondsPerBeat).round();
      final strong = beat % 4 == 0; // Сильная доля каждые 4 удара
      final linePaint = Paint()
        ..color = strong ? Colors.black : Colors.grey[400]!
        ..strokeWidth = strong ? 1.2 : 0.6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    // Рисуем область клавиатуры слева: белые и черные клавиши
    final white = Paint()..color = Colors.white;
    final black = Paint()..color = Colors.black87;
    for (var i = minNote; i <= maxNote; i++) {
      // Определяем, является ли текущий полутон черным ключом
      final isBlackKey = [1, 3, 6, 8, 10].contains(i % 12);
      final y = (maxNote - i) * noteHeight;
      canvas.drawRect(
        Rect.fromLTWH(0, y, keyWidth, noteHeight),
        isBlackKey ? black : white,
      );
    }

    // Рисуем рамку вокруг всего канваса
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
