import 'package:path_provider/path_provider.dart';
import 'dart:io';

Future<String> getTempAudioFilePath() async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
}

String formatDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
} 