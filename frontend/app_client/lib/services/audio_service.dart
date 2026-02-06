import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

// Use conditional import for IoHelper
import '../utils/io_helper.dart' if (dart.library.html) '../utils/io_helper_web.dart';
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;

class AudioService {
  static final AudioRecorder _audioRecorder = AudioRecorder();
  
  /// Starts recording with specs optimized for Gemini 2.0 Flash
  /// 16kHz, Mono, AAC_LC (m4a)
  static Future<void> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        String? filePath;
        
        if (!kIsWeb) {
          final directory = await getApplicationDocumentsDirectory();
          filePath = p.join(directory.path, 'ayla_audio_prompt.m4a');
          
          // Delete existing file if it exists using IoHelper
          await IoHelper.deleteFile(filePath);
        }

        // Use platform-specific encoder: 
        // - Web: Opus (better browser support, AAC may not be supported)
        // - Mobile: AAC LC (optimal for Gemini)
        final config = RecordConfig(
          encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 16000, // Optimized for Gemini
          numChannels: 1,    // Mono
        );

        // On Web, path is ignored and it returns a blob URL in stop()
        await _audioRecorder.start(config, path: filePath ?? '');
        debugPrint("Recording started${filePath != null ? ': $filePath' : ' (Web)'}");
      } else {
        throw Exception("Microphone permission denied");
      }
    } catch (e) {
      debugPrint("Error starting recording: $e");
      rethrow;
    }
  }

  /// Stops recording and returns the file path (or blob URL on web)
  static Future<String?> stopRecording() async {
    try {
      final String? path = await _audioRecorder.stop();
      debugPrint("Recording stopped: $path");
      return path;
    } catch (e) {
      debugPrint("Error stopping recording: $e");
      return null;
    }
  }

  /// Checks if currently recording
  static Future<bool> isRecording() async {
    return await _audioRecorder.isRecording();
  }

  /// Cleans up
  static void dispose() {
    _audioRecorder.dispose();
  }
}
