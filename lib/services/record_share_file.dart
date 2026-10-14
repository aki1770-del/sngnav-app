/// THE RECORD, SHARED AS A FILE (2026-10-10).
///
/// Why. The fix-interval record was shared as text: the whole record went
/// into the share intent's text extra. An emulator read on API 30 and API 34
/// showed that at the record's cap (about 197,000 characters) the system could
/// not deliver the chooser's launch: "TransactionTooLargeException: data
/// parcel size 593120 bytes", then "giving up". Nothing was sent, and the app
/// was told nothing; on API 34 its screen closed. The chooser opened up to
/// about 150,000 characters on API 34 and failed from about 170,000.
///
/// What this does instead. The text is written to a FILE, and the share sheet
/// is handed the file. share_plus 13.3.0 (the locked version) then puts only a
/// content link (`content://<app>.flutter.share_provider/...`, a few dozen
/// bytes) in the intent's stream extra (android/.../Share.kt:145-155, :240).
/// The receiver reads the bytes through share_plus's FileProvider, by a file
/// descriptor, outside the transaction that carries the intent. So the size
/// of the record never enters the intent, and the parcel limit that failed
/// cannot be reached by the record's size.
///
/// The copies are the record too. Two copies exist while a share runs, both in
/// the app's CACHE directory (path_provider's getTemporaryDirectory() is
/// Android's getCacheDir()):
/// - [RecordShareFile.staged]: the text this app writes for the share sheet,
///   in `<cache>/record_share/`. Deleted as soon as the share call returns,
///   whatever it returned: no receiver reads it.
/// - [RecordShareFile.sharePlusCopies]: share_plus copies every shared file
///   into `<cache>/share_plus/<same name>` before it launches the sheet
///   (Share.kt:297-305), and deletes that folder only at its next share
///   (:119, :287-294). This is the copy the receiver reads. It is KEPT after
///   the share, because a receiver may open the link after he is back in the
///   app (2026-10-10): the page deletes it at his next 記録を共有, at the next
///   launch, and at 記録を消す.
///
/// EACH SHARE HAS ITS OWN NAME (2026-10-10). With one fixed name, a receiver
/// that still held the link of one share read the NEXT share's bytes, 159 s
/// later, on an emulator: a destination he chose for one share received a
/// share he never sent there. Each share's file is now named
/// `sngnav-fix-interval-record-<token>.txt`, the token random and holding no
/// time of day, and every copy is deleted by the name's prefix. An old link
/// then names a file that is gone, and its read fails rather than reading
/// another share's content.
/// Neither is backed up or moved to a new phone: Android excludes the cache
/// directory from every full backup, cloud and device transfer alike, whatever
/// the rules say (AOSP BackupAgent.java: android10-release :396, :424;
/// android14-release getExtraExcludeDirsIfAny :582-588; the Auto Backup page,
/// "always excluded even if you try to include them").
///
/// A failure here never takes the app down: every file operation is wrapped,
/// except [RecordShareFile.stage], which throws so the caller can say the
/// share could not be handed on.
library;

import 'dart:io' show Directory, File;
import 'dart:math' show Random;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Every share copy's name starts with this, on every build that shares the
/// fix-interval record, so any build can find and delete a copy another left
/// (the one fixed name earlier builds used, `sngnav-fix-interval-record.txt`,
/// starts with it too).
const String kRecordShareFilePrefix = 'sngnav-fix-interval-record';

/// The name of one share's file: the prefix, a token unique to the share, and
/// `.txt`. The receiver sees this name. It holds no time of day.
String recordShareFileName(String token) => '$kRecordShareFilePrefix-$token.txt';

/// This app's staging folder under the cache directory.
const String kRecordShareStagingDir = 'record_share';

/// share_plus 13.3.0's own folder under the cache directory (Share.kt:54).
const String kSharePlusCacheDir = 'share_plus';

/// The copies of a shared record, under one cache directory.
class RecordShareFile {
  RecordShareFile({required this.cacheDirectory, Random? random})
      : _random = random ?? Random.secure();

  /// The app's cache directory (Android's getCacheDir()).
  final Directory cacheDirectory;

  final Random _random;

  /// This app's staging folder.
  Directory get stagingDirectory =>
      Directory('${cacheDirectory.path}/$kRecordShareStagingDir');

  /// share_plus's folder, where the copy the receiver reads lives.
  Directory get sharePlusDirectory =>
      Directory('${cacheDirectory.path}/$kSharePlusCacheDir');

  /// A name for one share: 8 hex digits from a secure random source.
  String newShareFileName() => recordShareFileName(
      _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'));

  /// This app's staging copies on disk (by the name's prefix).
  List<File> get staged => _prefixed(stagingDirectory);

  /// share_plus's copies on disk (by the name's prefix).
  List<File> get sharePlusCopies => _prefixed(sharePlusDirectory);

  /// Writes [payload] to a staging file with a name of its own, and returns
  /// it. THROWS on failure, so the caller can tell him the record could not
  /// be handed to the share screen.
  File stage(String payload) {
    final f = File('${stagingDirectory.path}/${newShareFileName()}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(payload, flush: true);
    return f;
  }

  /// Deletes this app's staging copies, by the name's prefix. Never throws.
  void deleteStaged() => _deletePrefixed(stagingDirectory);

  /// Deletes share_plus's copies of the record, by the name's prefix. Never
  /// throws.
  void deleteSharePlusCopies() => _deletePrefixed(sharePlusDirectory);

  /// Deletes every copy: at 記録を消す and at launch.
  void deleteAll() {
    deleteStaged();
    deleteSharePlusCopies();
  }

  /// Whether any copy is on disk. True when the folders cannot be read.
  bool get anyCopy {
    try {
      return _list(stagingDirectory).isNotEmpty ||
          _list(sharePlusDirectory).isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  /// The record's copies in [d]: every file whose name starts with the
  /// prefix. THROWS when [d] exists but cannot be listed.
  static List<File> _list(Directory d) {
    if (!d.existsSync()) return const [];
    return [
      for (final e in d.listSync())
        if (e is File && e.uri.pathSegments.last.startsWith(kRecordShareFilePrefix)) e,
    ];
  }

  static List<File> _prefixed(Directory d) {
    try {
      return _list(d);
    } catch (_) {
      return const [];
    }
  }

  static void _deletePrefixed(Directory d) {
    for (final f in _prefixed(d)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}

/// The share copies under the app's cache directory, or null when it cannot
/// be resolved. Never throws.
Future<RecordShareFile?> openRecordShareFile({Directory? cacheDirectory}) async {
  try {
    return RecordShareFile(
        cacheDirectory: cacheDirectory ?? await getTemporaryDirectory());
  } catch (_) {
    return null;
  }
}

/// Injectable exit door: hands the file at [path] to the share sheet.
typedef RecordFileShareSink = Future<void> Function(String path);

/// Production [RecordFileShareSink]: the platform share sheet with the FILE,
/// as text/plain, and no text extra (the record never rides the intent).
Future<void> shareRecordFileViaShareSheet(String path, {required String subject}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: 'text/plain')],
      subject: subject,
    ),
  );
}
