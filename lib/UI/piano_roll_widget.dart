import 'dart:math'; 
 
import 'package:flutter/material.dart'; 
import 'package:pitch_to_midi/data/midi_note.dart'; 
import 'piano_roll_grid_painter.dart'; 
 
class PianoRollWidget extends StatefulWidget { 
  final List<MidiNote> notes;     // Список распознанных нот 
  final double noteHeight;        // Высота одного «тонового» ряда 
  final double secondsPerBeat;    // Длина одного удара (сек) 
 
  const PianoRollWidget({ 
    super.key, 
    required this.notes, 
    required this.noteHeight, 
    required this.secondsPerBeat, 
  }); 
 
  @override 
  PianoRollWidgetState createState() => PianoRollWidgetState(); 
} 
 
class PianoRollWidgetState extends State<PianoRollWidget> { 
  static const int minNote = 48; 
  static const int maxNote = 71; 
  static const double keyWidth = 30; 
  static const double pixelsPerSecond = 200; 
 
  int? selectedNoteIndex; 
 
  @override 
  Widget build(BuildContext context) { 
    // Полная высота сетки для всех нот 
    final pianoRollHeight = widget.noteHeight * (maxNote - minNote + 1); 
    // Максимальное время по всем нотам 
    final maxTime = widget.notes 
        .map((n) => n.start + n.duration) 
        .fold(0.0, (prev, element) => max(prev, element)); 
 
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