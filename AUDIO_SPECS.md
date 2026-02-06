# Audio Capture & Processing Guidelines (Gemini 2.0 Flash)

**Target Audience**: Flutter Development Team
**Context**: Optimizing audio uploads for the "Student AI Platform" to ensure high-fidelity transcription by Gemini 2.0 while minimizing bandwidth.

## 1. Technical Constraints

### Sample Rate: 16kHz (16,000 Hz)
- **Why?** Gemini uses a tokenizer that processes audio at approximately **32 tokens/second**.
- **Efficiency**: 16kHz is the Nyquist minimum for capturing human speech (up to 8kHz frequency) perfectly. Recording at 44.1kHz or 48kHz adds *zero* improved accuracy for speech-to-text but triples the file size.
- **Bandwidth**: Reduces upload time significantly, improving user experience on mobile data.

### Channels: Mono (1 Channel)
- **Why?** Spatial audio (Stereo) is irrelevant for voice prompts and lectures. Mono cuts file size in half compared to Stereo.

### Bitrate
- Recommended: **32 kbps - 64 kbps** (Opus or MP3).
- **Format**: `audio/mpeg` (MP3) or `audio/ogg` (Opus) or `audio/wav` (PCM).
    - **Preferred**: AAC or MP3 for broad compatibility, or WAV for raw quality if short.

---

## 2. Implementation Logic (Flutter)

### Recording Implementation
Configure your `flutter_sound` or `record` package with:
```dart
// Example config configuration
final config = RecordConfig(
  encoder: AudioEncoder.aacLc, // or mp3
  bitRate: 48000, 
  sampleRate: 16000, // CRITICAL: 16kHz
  numChannels: 1,    // Mono
);
```

### Upload Strategy (Backend Hand-off)
The backend (FastAPI) has a strict logic for handling files based on size to optimize for Gemini's entry points.

1.  **Capture Audio** -> `File` object.
2.  **Check Size**:
    - **< 20 MB**: Send as standard form-data. The backend will pass it as `inline_data` (Base64) to Gemini for instant response.
    - **> 20 MB**: Send as standard form-data. The backend will verify size and automatically route it to the **Resumable Uploads API** (Gemini Files API). 
        - *UX Note*: For large files, show a "Processing..." spinner as the backend might poll for the `ACTIVE` state.

## 3. Error Handling
- If the backend returns `400 Bad Request` with "Audio too long", suggest the user split the recording.
- If `503 Service Unavailable`, the upload to Gemini might have failed; retry with exponential backoff.
