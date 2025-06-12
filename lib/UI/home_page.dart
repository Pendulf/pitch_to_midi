import 'package:flutter/material.dart'; 
import 'package:pitch_to_midi/domain/audio_recorder.dart'; 
import 'package:pitch_to_midi/domain/playback.dart'; 
import 'package:pitch_to_midi/domain/metronome.dart'; 
import 'package:pitch_to_midi/data/midi_note.dart'; 
import 'piano_roll_widget.dart'; 
 
class HomePage extends StatefulWidget { 
  final AudioRecorderService audioRecorderService; 
  final PlaybackService playbackService; 
  final MetronomeService metronomeService; 
 
  const HomePage({ 
    super.key, 
    required this.audioRecorderService, 
    required this.playbackService, 
    required this.metronomeService, 
  }); 
 
  @override 
  HomePageState createState() => HomePageState(); 
} 
 
class HomePageState extends State<HomePage> { 
  static const int totalBars = 40; 
 
  // Словарь: MIDI-номер ноты → имя файла 
  static const Map<int, String> midiToFileName = { 
    48: 'c4.wav', 49: 'cs4.wav', 50: 'd4.wav', 51: 'ds4.wav', 
    52: 'e4.wav', 53: 'f4.wav', 54: 'fs4.wav', 55: 'g4.wav', 
    56: 'gs4.wav', 57: 'a4.wav', 58: 'as4.wav', 59: 'b4.wav', 
    60: 'c5.wav', 61: 'cs5.wav', 62: 'd5.wav', 63: 'ds5.wav', 
    64: 'e5.wav', 65: 'f5.wav', 66: 'fs5.wav', 67: 'g5.wav', 
    68: 'gs5.wav', 69: 'a5.wav', 70: 'as5.wav', 71: 'b5.wav', 
  }; 
 
  // Словарь: название инструмента → папка с его звуками 
  static const Map<String, String> instrumentFolders = { 
    'Пианино': 'piano', 
    'Флейта': 'flute', 
    'Ксилофон': 'xylophone', 
  }; 
 
  // Состояния UI 
  List<MidiNote> _notes = []; 
  bool _isRecording = false; 
  bool _isPlaying = false; 
  String _selectedInstrument = 'Пианино'; 
 
  late Stream<List<MidiNote>> _recordingStream; 
 
  @override 
  void initState() { 
    super.initState(); 
    // Инициализируем сервис записи (запрос прав) 
    widget.audioRecorderService.init(); 
    // Подписываемся на стрим мерцания метронома, чтобы обновлять UI 
    widget.metronomeService.flashStream.listen((_) { 
      setState(() {}); 
    }); 
  } 
 
  double get secondsPerBeat => 60.0 / widget.metronomeService.bpm; 
 
  /// Запуск записи: очищаем предыдущие данные и слушаем стрим barNotes 
  void _startRecording() { 
    if (_isPlaying) { 
      widget.playbackService.stop(); 
    } 
    setState(() { 
      _isRecording = true; 
      _notes.clear(); 
    }); 
 
    _recordingStream = 
        widget.audioRecorderService.startRecording(widget.metronomeService.bpm); 
    _recordingStream.listen((_) { 
      // Каждый раз, когда barNotes обновляется, получаем финальный список нот 
      setState(() { 
        _notes = widget.audioRecorderService.finalizeNotes(); 
      }); 
    }); 
  } 
 
  /// Остановка записи 
  void _stopRecording() { 
    widget.audioRecorderService.stopRecording(); 
    setState(() { 
      _isRecording = false; 
    }); 
  } 
 
  /// Запуск воспроизведения нот 
  void _playNotes() async { 
    setState(() { 
      _isPlaying = true; 
    }); 
    await widget.playbackService.playNotes( 
      _notes, 
      instrumentFolders[_selectedInstrument]!, 
      midiToFileName, 
    ); 
    setState(() { 
      _isPlaying = false; 
    }); 
  } 
 
  /// Остановка воспроизведения 
  void _stopPlayback() { 
    widget.playbackService.stop(); 
    setState(() { 
      _isPlaying = false; 
    }); 
  } 
 
  @override 
  void dispose() { 
    widget.audioRecorderService.dispose(); 
    widget.playbackService.stop(); 
    widget.metronomeService.dispose(); 
    super.dispose(); 
  } 
 
  @override 
  Widget build(BuildContext context) { 
    final screenHeight = MediaQuery.of(context).size.height; 
    final pianoRollHeight = screenHeight * 2 / 3; 
    final noteHeight = pianoRollHeight / 24; 
 
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
            const SizedBox(width: 200), 
            Align( 
              alignment: Alignment.centerLeft, 
              child: Padding( 
                padding: const EdgeInsets.only(left: 13), 
                child: Image.asset( 
                  'assets/image/logo.png', 
                  height: 25, 
                ), 
              ), 
            ), 
            Center( 
              child: Text( 
                _selectedInstrument, 
                style: const TextStyle( 
                  color: Colors.white, 
                  fontSize: 26, 
                  fontWeight: FontWeight.bold, 
                ), 
              ), 
            ), 
          ], 
        ), 
        bottom: const PreferredSize( 
          preferredSize: Size.fromHeight(2), 
          child: Divider(color: Colors.black, thickness: 4, height: 0), 
        ), 
      ), 
      body: Container( 
        color: Colors.grey[800], 
        child: Column( 
          children: [ 
            // Панель выбора инструмента и метронома 
            Container( 
              color: Colors.grey[900], 
              child: Row( 
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [ 
                  // Иконки инструментов 
                  Row( 
                    children: instrumentFolders.keys.map((instrument) { 
                      final isActive = _selectedInstrument == instrument; 
                      final folderName = instrumentFolders[instrument]!; 
                      return IconButton( 
                        iconSize: 40, 
                        onPressed: () { 
                          setState(() { 
                            _selectedInstrument = instrument; 
                          }); 
                        }, 
                        icon: Image.asset( 
                          // ignore: unnecessary_brace_in_string_interps 
                          'assets/icons/${folderName}${isActive ? "active" : "inactive"}.png', 
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
                    onTap: () { 
                      widget.metronomeService.tap(); 
                      setState(() {}); 
                    }, 
                    onLongPress: () { 
                      widget.metronomeService.toggle(); 
                      setState(() {}); 
                    }, 
                    onTapDown: (_) => setState(() {}), 
                    onTapUp: (_) => setState(() {}), 
                    onTapCancel: () => setState(() {}), 
                    child: Stack( 
                      alignment: Alignment.center, 
                      children: [ 
                        Image.asset( 
                          widget.metronomeService.isActive 
                              ? 'assets/icons/bpm_active.png' 
                              : 'assets/icons/bpm_idle.png', 
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
                              '${widget.metronomeService.bpm}', 
                              style: const TextStyle( 
                                fontSize: 14, 
                                fontWeight: FontWeight.w600, 
                                color: Colors.black, 
                                shadows: [Shadow(blurRadius: 2, color: Colors.black)], 
                              ), 
                            ), 
                          ], 
                        ), 
                        StreamBuilder<bool>( 
                          stream: widget.metronomeService.flashStream, 
                          initialData: false, 
                          builder: (context, snapshot) { 
                            return snapshot.data! 
                                ? Image.asset( 
                                    'assets/icons/bpm_active.png', 
                                    width: 65, 
                                    height: 65, 
                                  ) 
                                : const SizedBox(); 
                          }, 
                        ), 
                      ], 
                    ), 
                  ), 
                ], 
              ), 
            ), 
            const Divider(color: Colors.black, thickness: 4, height: 0), 
            // Область Piano Roll 
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
            const Divider(color: Colors.black, thickness: 4, height: 0), 
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
                      onPressed: _isRecording ? _stopRecording : _startRecording, 
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
                            : (_isPlaying ? _stopPlayback : _playNotes), 
                        child: Text(_isPlaying ? 'Сброс' : 'Играть'), 
                      ), 
                    ), 
                ], 
              ), 
            ), 
          ], 
        ), 
      ), 
    ); 
  } 
} 