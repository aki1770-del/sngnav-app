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
/// - [RecordShareFile.sharePlusCopy]: share_plus copies every shared file into
///   `<cache>/share_plus/<same name>` before it launches the sheet
///   (Share.kt:297-305), and deletes that folder only at its next share
///   (:119, :287-294). This is the copy the receiver reads. It is KEPT after
///   the share, because a receiver may open the link after he is back in the
///   app (2026-10-10): the page deletes it at his next 記録を共有, at the next
///   launch, and at 記録を消す.
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

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The file name the receiver sees, the same on every build that shares the
/// fix-interval record, so any build can find and delete a copy another left.
const String kRecordShareFileName = 'sngnav-fix-interval-record.txt';

/// This app's staging folder under the cache directory.
const String kRecordShareStagingDir = 'record_share';

/// share_plus 13.3.0's own folder under the cache directory (Share.kt:54).
const String kSharePlusCacheDir = 'share_plus';

/// The two copies of a shared record, under one cache directory.
class RecordShareFile {
  RecordShareFile({required this.cacheDirectory});

  /// The app's cache directory (Android's getCacheDir()).
  final Directory cacheDirectory;

  /// This app's copy, written for the share sheet.
  File get staged =>
      File('${cacheDirectory.path}/$kRecordShareStagingDir/$kRecordShareFileName');

  /// share_plus's copy of [staged], made before the sheet opens.
  File get sharePlusCopy =>
      File('${cacheDirectory.path}/$kSharePlusCacheDir/$kRecordShareFileName');

  /// Writes [payload] to [staged] and returns it. THROWS on failure, so the
  /// caller can tell him the record could not be handed to the share screen.
  File stage(String payload) {
    final f = staged;
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(payload, flush: true);
    return f;
  }

  /// Deletes this app's staging copy. Never throws.
  void deleteStaged() => _delete(staged);

  /// Deletes share_plus's copy. Never throws.
  void deleteSharePlusCopy() => _delete(sharePlusCopy);

  /// Deletes every copy: at 記録を消す and at launch.
  void deleteAll() {
    deleteStaged();
    deleteSharePlusCopy();
  }

  /// Whether any copy is on disk.
  bool get anyCopy {
    try {
      return staged.existsSync() || sharePlusCopy.existsSync();
    } catch (_) {
      return true;
    }
  }

  static void _delete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
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
