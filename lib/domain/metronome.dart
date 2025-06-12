import 'dart:async'; 
 
/// Сервис метронома: вычисляет BPM по тапам и мерцает 
class MetronomeService { 
  bool _active = false; 
  int _bpm = 120; 
  final List<DateTime> _tapTimes = []; 
  Timer? _timer; 
  final StreamController<bool> _flashController = StreamController<bool>.broadcast(); 
 
  /// Поток, который выдаёт true при каждом «мигании» (100 мс), иначе false 
  Stream<bool> get flashStream => _flashController.stream; 
 
  int get bpm => _bpm; 
  bool get isActive => _active; 
 
  /// Переключает состояние метронома (вкл/выкл) 
  void toggle() { 
    if (_active) { 
      _stop(); 
    } else { 
      _start(); 
    } 
  } 
 
  /// Обрабатывает тап: добавляет текущий TimeStamp, пересчитывает bpm 
  void tap() { 
    final now = DateTime.now(); 
    _tapTimes.add(now); 
    // Удаляем старые записи старше 2 сек назад 
    _tapTimes.removeWhere((t) => now.difference(t).inMilliseconds > 2000); 
    if (_tapTimes.length < 2) return; 
 
    final intervals = [ 
      for (int i = 1; i < _tapTimes.length; i++) 
        _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds 
    ];
final avgMs = intervals.reduce((a, b) => a + b) / intervals.length; 
    final newBpm = (60000 / avgMs).round().clamp(40, 240); 
    _bpm = newBpm; 
 
    // Если метроном активен, перезапускаем под новый темп 
    if (_active) { 
      _stop(); 
      _start(); 
    } 
  } 
 
  void _start() { 
    _timer?.cancel(); 
    final interval = Duration(milliseconds: (60000 / _bpm).round()); 
    _timer = Timer.periodic(interval, (_) { 
      _flashController.add(true); 
      Future.delayed(const Duration(milliseconds: 100), () { 
        _flashController.add(false); 
      }); 
    }); 
    _active = true; 
  } 
 
  void _stop() { 
    _timer?.cancel(); 
    _active = false; 
    _flashController.add(false); 
  } 
 
  void dispose() { 
    _timer?.cancel(); 
    _flashController.close(); 
  } 
} 