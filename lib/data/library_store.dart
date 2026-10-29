import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../format.dart';
import '../models.dart';
import 'adts.dart';

enum SortMode { newest, oldest, name }

/// A search result. When the match is in the transcript, [snippet] holds the
/// surrounding text, [match] its position inside the snippet, and [at] where
/// that speech starts in the audio.
class SearchHit {
  const SearchHit(this.recording, {this.snippet, this.match, this.at});

  final Recording recording;
  final String? snippet;
  final (int, int)? match;
  final Duration? at;
}

class TranscriptionSettings {
  /// Installed Whisper model id; null while transcription is off.
  String? modelId;
  bool autoTranscribe = false;

  Map<String, Object?> toJson() => {'modelId': modelId, 'autoTranscribe': autoTranscribe};

  void readJson(Map<String, Object?>? j) {
    modelId = j?['modelId'] as String?;
    autoTranscribe = j?['autoTranscribe'] as bool? ?? false;
  }
}

/// Owns all folders and recordings and persists them to `library.json`.
///
/// Writes are atomic (temp file + rename, previous version kept as `.bak`)
/// and serialized, so a crash mid-write never leaves the library unreadable.
/// [load] also repairs the state left by an unexpected shutdown.
class LibraryStore extends ChangeNotifier {
  LibraryStore(this.root);

  final Directory root;
  final List<Folder> folders = [];
  final List<Recording> recordings = [];
  final transcription = TranscriptionSettings();

  /// Recordings rescued by the last [load]; the UI reports it once.
  int recoveredOnLoad = 0;

  Directory get audioDir => Directory('${root.path}${Platform.pathSeparator}audio');
  Directory get modelsDir => Directory('${root.path}${Platform.pathSeparator}models');
  File get _main => File('${root.path}${Platform.pathSeparator}library.json');
  File get _tmp => File('${_main.path}.tmp');
  File get _bak => File('${_main.path}.bak');

  File audioFile(Recording r) => File('${audioDir.path}${Platform.pathSeparator}${r.fileName}');

  Future<void> _pending = Future.value();
  final _random = Random.secure();

  String _newId() =>
      List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  // ---------------------------------------------------------------- loading

  Future<void> load() async {
    await audioDir.create(recursive: true);
    folders.clear();
    recordings.clear();
    recoveredOnLoad = 0;

    // A complete temp file is newer than the main one (crash before rename);
    // a truncated one fails to parse and the next candidate is used.
    for (final f in [_tmp, _main, _bak]) {
      final data = await _tryRead(f);
      if (data == null) continue;
      folders.addAll([for (final j in data['folders'] as List) Folder.fromJson(j as Map<String, Object?>)]);
      recordings.addAll([for (final j in data['recordings'] as List) Recording.fromJson(j as Map<String, Object?>)]);
      transcription.readJson(data['settings'] as Map<String, Object?>?);
      break;
    }

    if (await _repair()) await _persist();
  }

  Future<Map<String, Object?>?> _tryRead(File f) async {
    try {
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, Object?>;
      if (data['folders'] is! List || data['recordings'] is! List) return null;
      return data;
    } on Object {
      return null;
    }
  }

  /// Finalizes recordings interrupted by a crash, adopts audio files the
  /// metadata lost, and drops dangling folder references. Returns whether
  /// anything changed.
  Future<bool> _repair() async {
    var changed = false;
    final folderIds = {for (final f in folders) f.id};

    for (final r in List.of(recordings)) {
      final file = audioFile(r);
      final exists = await file.exists() && await file.length() > 0;
      if (r.status == RecordingStatus.recording) {
        changed = true;
        if (!exists) {
          recordings.remove(r);
          continue;
        }
        r.duration = await _finalizeAudio(file);
        r.status = RecordingStatus.ready;
        r.recovered = true;
        recoveredOnLoad++;
      }
      r.fileMissing = !exists;
      // A transcription cut off by the app closing is reported, not retried
      // automatically, in case it was what brought the app down.
      if (r.transcriptStatus == TranscriptStatus.running) {
        r
          ..transcriptStatus = TranscriptStatus.failed
          ..transcriptError = 'A transcrição foi interrompida antes de terminar.';
        changed = true;
      }
      if (r.folderId != null && !folderIds.contains(r.folderId)) {
        r.folderId = null;
        changed = true;
      }
    }

    final known = {for (final r in recordings) r.fileName};
    await for (final e in audioDir.list()) {
      if (e is! File || !e.path.endsWith('.aac')) continue;
      final name = e.uri.pathSegments.last;
      if (known.contains(name) || await e.length() == 0) continue;
      final created = await e.lastModified();
      recordings.add(Recording(
        id: _newId(),
        name: suggestedName(created),
        createdAt: created,
        fileName: name,
        duration: await _finalizeAudio(e),
        recovered: true,
      ));
      recoveredOnLoad++;
      changed = true;
    }
    return changed;
  }

  /// Returns the exact duration and cuts a partial trailing frame, if any.
  Future<Duration> _finalizeAudio(File file) async {
    final scan = scanAdts(await file.readAsBytes());
    if (scan.validLength > 0 && scan.validLength < await file.length()) {
      final raf = await file.open(mode: FileMode.append);
      await raf.truncate(scan.validLength);
      await raf.close();
    }
    return scan.duration;
  }

  /// Exact duration of a finished recording file.
  Future<Duration> measure(Recording r) async => scanAdts(await audioFile(r).readAsBytes()).duration;

  // ---------------------------------------------------------------- persistence

  Future<void> _persist() {
    final data = jsonEncode({
      'version': 1,
      'folders': [for (final f in folders) f.toJson()],
      'recordings': [for (final r in recordings) r.toJson()],
      'settings': transcription.toJson(),
    });
    final write = _pending.then((_) => _writeAtomically(data));
    _pending = write.catchError((Object _) {});
    notifyListeners();
    return write;
  }

  Future<void> _writeAtomically(String data) async {
    await _tmp.writeAsString(data, flush: true);
    if (await _main.exists()) await _main.copy(_bak.path);
    await _tmp.rename(_main.path);
  }

  // ---------------------------------------------------------------- queries

  Folder? folderById(String? id) => id == null ? null : folders.where((f) => f.id == id).firstOrNull;

  List<Recording> inFolder(String? folderId) =>
      [for (final r in _ready) if (r.folderId == folderId) r];

  Iterable<Recording> get _ready => recordings.where((r) => r.status == RecordingStatus.ready);

  List<Recording> get allReady => _ready.toList();

  int countIn(String? folderId) => _ready.where((r) => r.folderId == folderId).length;

  DateTime? lastRecordingIn(String? folderId) {
    DateTime? last;
    for (final r in _ready) {
      if (r.folderId == folderId && (last == null || r.createdAt.isAfter(last))) last = r.createdAt;
    }
    return last;
  }

  /// Matches name, folder name, date (dd/mm/aaaa), time and the transcript,
  /// accent-insensitively. Every term must appear somewhere.
  List<SearchHit> search(String query) {
    final terms = normalize(query).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return [
      for (final r in _ready)
        if (_matches(r, terms)) _hit(r, terms),
    ];
  }

  bool _matches(Recording r, List<String> terms) {
    final meta = _haystack(r);
    final spoken = normalize(r.transcriptText);
    return terms.every((t) => meta.contains(t) || spoken.contains(t));
  }

  String _haystack(Recording r) => normalize(
      '${r.name} ${folderById(r.folderId)?.name ?? 'sem pasta'} ${formatDate(r.createdAt)} ${formatTime(r.createdAt)}');

  static const _snippetBefore = 40;
  static const _snippetAfter = 60;

  SearchHit _hit(Recording r, List<String> terms) {
    final text = r.transcriptText;
    final spoken = normalize(text);
    // Positions only line up when normalizing kept the length (it maps one
    // character to one character for Portuguese text).
    if (spoken.length != text.length) return SearchHit(r);
    for (final t in terms) {
      final i = spoken.indexOf(t);
      if (i < 0) continue;
      Duration? at;
      var offset = 0;
      for (final s in r.transcript) {
        if (i < offset + s.text.length + 1) {
          at = s.start;
          break;
        }
        offset += s.text.length + 1;
      }
      final from = max(0, i - _snippetBefore);
      final to = min(text.length, i + t.length + _snippetAfter);
      final lead = from > 0 ? '…' : '';
      final snippet = '$lead${text.substring(from, to)}${to < text.length ? '…' : ''}';
      final start = lead.length + i - from;
      return SearchHit(r, snippet: snippet, match: (start, start + t.length), at: at);
    }
    return SearchHit(r);
  }

  // ---------------------------------------------------------------- transcription

  Future<void> saveTranscriptionSettings() => _persist();

  Future<void> setTranscriptStatus(Recording r, TranscriptStatus status, {String? error}) {
    r
      ..transcriptStatus = status
      ..transcriptError = error;
    return _persist();
  }

  Future<void> saveTranscript(Recording r, List<TranscriptSegment> segments) {
    r
      ..transcript = segments
      ..transcriptStatus = TranscriptStatus.done
      ..transcriptError = null;
    return _persist();
  }

  static List<Recording> sorted(List<Recording> list, SortMode mode) => list
    ..sort(switch (mode) {
      SortMode.newest => (a, b) => b.createdAt.compareTo(a.createdAt),
      SortMode.oldest => (a, b) => a.createdAt.compareTo(b.createdAt),
      SortMode.name => (a, b) => normalize(a.name).compareTo(normalize(b.name)),
    });

  List<Folder> sortedFolders(SortMode mode) {
    final list = List.of(folders);
    DateTime activity(Folder f) => lastRecordingIn(f.id) ?? f.createdAt;
    list.sort(switch (mode) {
      SortMode.newest => (a, b) => activity(b).compareTo(activity(a)),
      SortMode.oldest => (a, b) => a.createdAt.compareTo(b.createdAt),
      SortMode.name => (a, b) => normalize(a.name).compareTo(normalize(b.name)),
    });
    return list;
  }

  // ---------------------------------------------------------------- recordings

  /// Registers a recording before any audio is captured, so a crash during
  /// recording is detected and repaired on the next [load].
  Future<Recording> beginRecording(DateTime now) async {
    final id = _newId();
    final r = Recording(
      id: id,
      name: suggestedName(now),
      createdAt: now,
      fileName: '$id.aac',
      status: RecordingStatus.recording,
    );
    recordings.add(r);
    await _persist();
    return r;
  }

  /// Marks a recording as done; it lands in "Sem pasta" until organized.
  Future<void> finishRecording(Recording r, Duration duration, List<int> waveform) {
    r
      ..duration = duration
      ..waveform = waveform
      ..status = RecordingStatus.ready;
    return _persist();
  }

  Future<void> updateRecording(Recording r, {String? name, required String? folderId}) {
    if (name != null && name.trim().isNotEmpty) r.name = name.trim();
    r.folderId = folderId;
    return _persist();
  }

  Future<void> renameRecording(Recording r, String name) =>
      updateRecording(r, name: name, folderId: r.folderId);

  /// Moving only changes the logical location; the audio file stays put.
  Future<void> moveRecording(Recording r, String? folderId) => updateRecording(r, folderId: folderId);

  Future<void> deleteRecording(Recording r) async {
    recordings.remove(r);
    await _persist();
    final f = audioFile(r);
    if (await f.exists()) await f.delete();
  }

  // ---------------------------------------------------------------- folders

  Future<Folder> createFolder(String name) async {
    final f = Folder(id: _newId(), name: name.trim(), createdAt: DateTime.now());
    folders.add(f);
    await _persist();
    return f;
  }

  Future<void> renameFolder(Folder f, String name) {
    f.name = name.trim();
    return _persist();
  }

  /// Deletes a folder; its recordings go to "Sem pasta" unless
  /// [deleteRecordings] is set.
  Future<void> deleteFolder(Folder f, {required bool deleteRecordings}) async {
    final contained = recordings.where((r) => r.folderId == f.id).toList();
    folders.remove(f);
    for (final r in contained) {
      if (deleteRecordings) {
        recordings.remove(r);
      } else {
        r.folderId = null;
      }
    }
    await _persist();
    if (deleteRecordings) {
      for (final r in contained) {
        final file = audioFile(r);
        if (await file.exists()) await file.delete();
      }
    }
  }
}
