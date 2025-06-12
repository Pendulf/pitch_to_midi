import 'package:flutter/material.dart'; 
 
class PianoRollGridPainter extends CustomPainter { 
  final double noteHeight;     // Высота одного ряда 
  final double secondsPerBeat; // Длительность удара (сек) 
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
    // Рисуем фон 
    final bg = Paint()..color = Colors.grey[200]!; 
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg); 
 
    // Горизонтальные линии (каждый полутон) 
    final grid = Paint() 
      ..color = Colors.grey 
      ..style = PaintingStyle.stroke 
      ..strokeWidth = 0.5; 
    for (var i = minNote; i <= maxNote; i++) { 
      final y = (maxNote - i) * noteHeight; 
      canvas.drawLine(Offset(keyWidth, y), Offset(size.width, y), grid); 
    } 
 
    // Вертикальные линии (каждый удар) 
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
 
    // Область клавиатуры слева: белые и черные клавиши 
    final white = Paint()..color = Colors.white; 
    final black = Paint()..color = Colors.black87; 
    for (var i = minNote; i <= maxNote; i++) { 
      final isBlackKey = [1, 3, 6, 8, 10].contains(i % 12); 
      final y = (maxNote - i) * noteHeight; 
      canvas.drawRect( 
        Rect.fromLTWH(0, y, keyWidth, noteHeight), 
        isBlackKey ? black : white, 
      ); 
    } 
 
    // Рамка вокруг всего канваса 
    final border = Paint() 
      ..color = Colors.black 
      ..style = PaintingStyle.stroke 
      ..strokeWidth = 2; 
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), border); 
  } 
 
  @override 
  bool shouldRepaint(covariant CustomPainter old) => true; 
} 