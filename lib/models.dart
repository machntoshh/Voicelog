/// Data models persisted in `library.json`.
library;

enum RecordingStatus { recording, ready }

enum TranscriptStatus { none, pending, running, done, failed }

/// A piece of transcribed speech and where it starts in the audio.
class TranscriptSegment {
  const TranscriptSegment(this.start, this.text);

  final Duration start;
  final String text;

  Map<String, Object?> toJson() => {'s': start.inMilliseconds, 't': text};

  factory TranscriptSegment.fromJson(Map<String, Object?> j) =>
      TranscriptSegment(Duration(milliseconds: (j['s']! as num).toInt()), j['t']! as String);
}

class Folder {
  Folder({required this.id, required this.name, required this.createdAt});

  final String id;
  String name;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Folder.fromJson(Map<String, Object?> j) => Folder(
        id: j['id']! as String,
        name: j['name']! as String,
        createdAt: DateTime.parse(j['createdAt']! as String),
      );
}

class Recording {
  Recording({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.fileName,
    this.duration = Duration.zero,
    this.folderId,
    this.status = RecordingStatus.ready,
    this.recovered = false,
    this.waveform = const [],
    this.transcriptStatus = TranscriptStatus.none,
    this.transcript = const [],
    this.transcriptError,
  });

  final String id;
  String name;
  final DateTime createdAt;

  /// File name inside the library's audio directory. Never changes, so moving
  /// or renaming a recording only touches metadata.
  final String fileName;
  Duration duration;

  /// `null` means "Sem pasta".
  String? folderId;
  RecordingStatus status;

  /// True when the recording was rescued after an unexpected shutdown.
  bool recovered;

  /// Peak levels (0–100) sampled while recording; empty when unknown.
  List<int> waveform;

  /// Optional speech-to-text result; the audio itself is never modified.
  TranscriptStatus transcriptStatus;
  List<TranscriptSegment> transcript;
  String? transcriptError;

  String get transcriptText => transcript.map((s) => s.text).join(' ');

  /// Set at load time when the audio file is gone; not persisted.
  bool fileMissing = false;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'fileName': fileName,
        'durationMs': duration.inMilliseconds,
        'folderId': folderId,
        'status': status.name,
        'recovered': recovered,
        'waveform': waveform,
        'transcriptStatus': transcriptStatus.name,
        'transcript': [for (final s in transcript) s.toJson()],
        'transcriptError': transcriptError,
      };

  factory Recording.fromJson(Map<String, Object?> j) => Recording(
        id: j['id']! as String,
        name: j['name']! as String,
        createdAt: DateTime.parse(j['createdAt']! as String),
        fileName: j['fileName']! as String,
        duration: Duration(milliseconds: (j['durationMs'] as num?)?.toInt() ?? 0),
        folderId: j['folderId'] as String?,
        status: RecordingStatus.values.asNameMap()[j['status']] ?? RecordingStatus.ready,
        recovered: j['recovered'] as bool? ?? false,
        waveform: [for (final v in (j['waveform'] as List?) ?? const []) (v as num).toInt()],
        transcriptStatus:
            TranscriptStatus.values.asNameMap()[j['transcriptStatus']] ?? TranscriptStatus.none,
        transcript: [
          for (final s in (j['transcript'] as List?) ?? const [])
            TranscriptSegment.fromJson(s as Map<String, Object?>),
        ],
        transcriptError: j['transcriptError'] as String?,
      );
}
