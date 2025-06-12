import 'dart:async'; 
import 'dart:math'; 
import 'dart:typed_data'; 
 
import 'package:flutter_sound/flutter_sound.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
 
import 'pitch_detector.dart'; 
import 'package:pitch_to_midi/data/midi_note.dart'; 
 
/// Сервис для записи аудио, распознавания частоты и формирования списка MidiNote. 
class AudioRecorderService { 
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder(); 
  final PitchDetector _pitchDetector = PitchDetector(); 
 
  StreamController<Uint8List>? _streamController; 
  StreamSubscription<Uint8List>? _streamSubscription; 
 
  final List<double> _buffer = []; 
  final List<int> _currentBarNotes = []; 
  int _currentBarIndex = 0; 
  final List<MidiNote> _barNotes = []; 
  DateTime? _startTime; 
  bool _isRecording = false; 
 
  static const int totalBars = 40; 
 
  /// Инициализация: запрос прав на микрофон 
  Future<void> init() async { 
    final status = await Permission.microphone.request(); 
    if (!status.isGranted) { 
      throw Exception('Microphone permission not granted'); 
    } 
    await _recorder.openRecorder(); 
  } 
 
  /// Запускает запись. Возвращает стрим обновлённых barNotes (для визуализации прогресса). 
  Stream<List<MidiNote>> startRecording(int bpm) async* { 
    _buffer.clear(); 
    _barNotes.clear(); 
    _currentBarNotes.clear(); 
    _currentBarIndex = 0; 
    _startTime = DateTime.now(); 
    _isRecording = true; 
 
    _streamController = StreamController<Uint8List>(); 
    _streamSubscription = _streamController!.stream.listen((chunk) { 
      _processAudio(chunk, bpm); 
    }); 
    await _recorder.startRecorder( 
      toStream: _streamController!.sink, 
      codec: Codec.pcm16, 
      sampleRate: _pitchDetector.sampleRate, 
      numChannels: 1, 
    ); 
 
    // Пока запись активна, постоянно выдаём текущее состояние barNotes 
    while (_isRecording) { 
      await Future.delayed(const Duration(milliseconds: 100)); 
      yield List.unmodifiable(_barNotes); 
    } 
  } 
 
  void _processAudio(Uint8List buffer, int bpm) { 
    final byteData = ByteData.sublistView(buffer); 
    for (int i = 0; i < byteData.lengthInBytes; i += 2) { 
      _buffer.add(byteData.getInt16(i, Endian.little) / 32768.0); 
    } 
 
    final secondsPerBeat = 60.0 / bpm; 
    // Обрабатываем «окна» по 8820 семплов (~0.2 сек) с перекрытием 50% 
    while (_buffer.length >= 8820) { 
      final chunk = _buffer.sublist(0, 8820);
_buffer.removeRange(0, 4410); 
 
      // Вычисляем RMS, чтобы игнорировать тишину 
      final rms = sqrt(chunk.fold<double>(0, (sum, x) => sum + x * x) / chunk.length); 
      if (rms < 0.02) continue; 
 
      // Детектируем частоту 
      final freq = _pitchDetector.detectPitch(chunk); 
      if (freq == null) continue; 
      final midi = _pitchDetector.frequencyToMidi(freq); 
 
      final now = DateTime.now(); 
      final timeElapsed = now.difference(_startTime!).inMilliseconds / 1000.0; 
      final maxDuration = totalBars * secondsPerBeat; 
      if (timeElapsed >= maxDuration && _isRecording) { 
        stopRecording(); 
        return; 
      } 
 
      final barIndex = (timeElapsed ~/ secondsPerBeat).clamp(0, totalBars - 1); 
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
      _currentBarNotes.add(midi); 
    } 
  } 
 
  /// Останавливает запись и сохраняет последнюю ноту бара, если она есть 
  void stopRecording() async { 
    _isRecording = false; 
    await _recorder.stopRecorder(); 
    await _streamSubscription?.cancel(); 
    await _streamController?.close(); 
 
    if (_currentBarNotes.isNotEmpty) { 
      final mostCommon = _mostFrequentNote(_currentBarNotes); 
      final secondsPerBeat = 
          60.0 / (_barNotes.isNotEmpty ? _barNotes[0].duration : 60); 
      _barNotes.add(MidiNote( 
        mostCommon, 
        _currentBarIndex * secondsPerBeat, 
        secondsPerBeat, 
      )); 
    } 
  } 
 
  /// Возвращает итоговый отфильтрованный список MidiNote для воспроизведения 
  List<MidiNote> finalizeNotes() { 
    final List<MidiNote> result = []; 
    final valid = _barNotes.where((n) => n.pitch != -1).toList(); 
    if (valid.isEmpty) return result; 
    final minStart = valid.map((n) => n.start).reduce(min); 
    for (var n in valid) { 
      result.add(MidiNote(n.pitch, n.start - minStart, n.duration)); 
    } 
    _barNotes.clear(); 
    return result; 
  } 
 
  int _mostFrequentNote(List<int> notes) { 
    final freqMap = <int, int>{}; 
    for (var n in notes) { 
      freqMap[n] = (freqMap[n] ?? 0) + 1; 
    } 
    return freqMap.entries.reduce((a, b) => a.value > b.value ? a : b).key; 
  } 
 
  void dispose() { 
    _streamSubscription?.cancel(); 
    _streamController?.close(); 
    _recorder.closeRecorder(); 
  } 
} 