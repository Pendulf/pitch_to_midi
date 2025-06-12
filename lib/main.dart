import 'package:flutter/material.dart'; 
import 'package:flutter/services.dart'; 
import 'package:pitch_to_midi/ui/home_page.dart'; 
import 'package:pitch_to_midi/domain/audio_recorder.dart'; 
import 'package:pitch_to_midi/domain/playback.dart'; 
import 'package:pitch_to_midi/domain/metronome.dart'; 
 
void main() async { 
  WidgetsFlutterBinding.ensureInitialized(); 
  // Фиксируем портретную ориентацию экрана 
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); 
  runApp(const MyApp()); 
} 
 
class MyApp extends StatelessWidget { 
  const MyApp({super.key}); 
 
  @override 
  Widget build(BuildContext context) { 
    return MaterialApp( 
      home: HomePage( 
        audioRecorderService: AudioRecorderService(), 
        playbackService: PlaybackService(), 
        metronomeService: MetronomeService(), 
      ), 
    ); 
  } 
} 