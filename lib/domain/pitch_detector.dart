import 'dart:math'; 
 
/// Сервис для детектирования частоты и перевода в MIDI-номер 
class PitchDetector { 
  final int sampleRate; 
 
  PitchDetector({this.sampleRate = 44100}); 
 
  /// Пытается найти частоту ноты в массиве [samples]. 
  /// Использует метод автокорреляции, возвращает частоту в Гц или null 
  double? detectPitch(List<double> samples) { 
    final size = samples.length; 
    final maxLag = min(1000, size ~/ 2); 
    double bestCorr = 0; 
    int bestLag = 0; 
    for (var lag = 50; lag < maxLag; lag++) { 
      double corr = 0; 
      for (var i = 0; i < size - lag; i++) { 
        corr += samples[i] * samples[i + lag]; 
      } 
      if (corr > bestCorr) { 
        bestCorr = corr; 
        bestLag = lag; 
      } 
    } 
    if (bestLag == 0) return null; 
    final freq = sampleRate / bestLag; 
    // Игнорируем нерелевантные частоты 
    return (freq < 50 || freq > 1000) ? null : freq; 
  } 
 
  /// Преобразует частоту [freq] (Гц) в MIDI-номер 
  int frequencyToMidi(double freq) { 
    return (69 + 12 * (log(freq / 440) / ln2)).round(); 
  } 
} 