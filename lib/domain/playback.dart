import 'dart:async'; 
import 'dart:math'; 
 
import 'package:audioplayers/audioplayers.dart'; 
import 'package:pitch_to_midi/data/midi_note.dart'; 
 
/// Сервис для воспроизведения списка нот (MidiNote) 
class PlaybackService { 
  final List<AudioPlayer> _players = []; 
  bool _isPlaying = false; 
 
  /// Проигрывает [notes] для инструмента из папки [instrumentFolder]   
  /// Использует словарь [midiToFileName] для поиска файла по pitch. 
  Future<void> playNotes( 
    List<MidiNote> notes, 
    String instrumentFolder, 
    Map<int, String> midiToFileName, 
  ) async { 
    _isPlaying = true; 
    _players.clear(); 
 
    for (var note in notes) { 
      final fileName = midiToFileName[note.pitch]; 
      if (fileName == null) continue; 
      final player = AudioPlayer(); 
      _players.add(player); 
 
      // Запускаем каждый звук ровно в момент note.start 
      Future.delayed( 
        Duration(milliseconds: (note.start * 1000).round()), 
        () { 
          if (_isPlaying) { 
            player.play(AssetSource('sounds/$instrumentFolder/$fileName')); 
          } 
        }, 
      ); 
    } 
 
    if (notes.isNotEmpty) { 
      final totalDuration = notes.map((n) => n.start + n.duration).reduce(max); 
      await Future.delayed( 
        Duration(milliseconds: (totalDuration * 1000).round()), 
      ); 
    } 
 
    _isPlaying = false; 
  } 
 
  /// Останавливает всё воспроизведение 
  void stop() { 
    for (var p in _players) { 
      p.stop(); 
    } 
    _players.clear(); 
    _isPlaying = false; 
  } 
 
  bool get isPlaying => _isPlaying; 
} 