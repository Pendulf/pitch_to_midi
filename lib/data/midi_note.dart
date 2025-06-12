/// Модель для хранения данных о MIDI-ноте 
class MidiNote { 
  final int pitch;       // Высота ноты в MIDI-формате 
  final double start;    // Время начала ноты (в секундах) 
  final double duration; // Длительность ноты (в секундах) 
 
  MidiNote(this.pitch, this.start, this.duration); 
} 