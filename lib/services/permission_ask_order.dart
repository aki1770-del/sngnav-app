/// One permission dialog at a time.
///
/// WHY THIS EXISTS, measured rather than reasoned (2026-10-02).
///
/// Android shows one permission dialog at a time. A request made while
/// another permission dialog is up is DROPPED: the platform logs
/// `W/Activity: Can request only one set of permissions at a time` and
/// answers the second request with an empty result. geolocator_android 4.6.2
/// treats an empty result as nothing to report and calls neither callback
/// (`PermissionManager.onRequestPermissionsResult`), so the Dart future of a
/// dropped location request never completes.
///
/// That is what happened on the first drive after a fresh install, on an
/// API 34 emulator, in two release builds: the drive start asked for the
/// notification permission without waiting, then asked for location while
/// the notification dialog was still up. She allowed notifications, no
/// location dialog followed, and she waited two minutes on
/// 現在地を取得しています… with no position and no dialog to answer. Below
/// Android 13 there is no runtime notification permission, so no second
/// dialog, and no race.
///
/// So the location request now waits for the earlier ask to answer. The wait
/// has two bounds, because there are two different reasons an answer may not
/// come:
///
/// - **A platform that does not answer.** The notification ask is made
///   through a channel, and a channel can fail to reply (measured under the
///   widget-test binding, where an unmocked channel never completes). Her
///   drive must not wait on that: if no answer has come after
///   [silentPlatformBound] (10 s, the same bound the position stream gives
///   every programmatic platform call) and nothing covers the app, the wait
///   ends and the drive goes on with what is already known.
/// - **A person reading a dialog.** While a permission dialog is in front,
///   the app is not in the foreground (Android pauses the activity behind
///   it). A reader slower than 10 s is not a silent platform, and ending the
///   wait under her dialog would make exactly the request Android drops. So
///   while the app is covered the wait continues, up to [dialogBound]: the
///   same two minutes the location dialog itself is given.
library;

import 'dart:async';

/// Resolves once [ask] has answered, so that the next permission request is
/// not made while the dialog [ask] raised may still be on her screen.
///
/// Also resolves after [silentPlatformBound] when [appInFront] says nothing
/// covers the app, and after [dialogBound] in any case. Never throws: an
/// error from [ask] counts as its answer.
Future<void> afterEarlierPermissionAsk(
  Future<void> ask, {
  required bool Function() appInFront,
  Duration silentPlatformBound = const Duration(seconds: 10),
  Duration dialogBound = const Duration(minutes: 2),
  Duration recheckEvery = const Duration(seconds: 1),
}) {
  final done = Completer<void>();
  Timer? recheck;
  Timer? capTimer;
  void finish() {
    recheck?.cancel();
    capTimer?.cancel();
    if (!done.isCompleted) done.complete();
  }

  unawaited(ask.then((_) => finish(), onError: (Object _) => finish()));
  void check() {
    if (done.isCompleted) return;
    if (appInFront()) {
      finish();
    } else {
      recheck = Timer(recheckEvery, check);
    }
  }

  recheck = Timer(silentPlatformBound, check);
  capTimer = Timer(dialogBound, finish);
  return done.future;
}

/// A stream that is started by [start] only once [ready] has resolved.
///
/// Cancelling before then means [start] is never called: a drive she ended
/// while it waited does not go on to ask or subscribe anything.
Stream<T> startWhenReady<T>(Future<void> ready, Stream<T> Function() start) {
  StreamSubscription<T>? inner;
  var cancelled = false;
  late final StreamController<T> out;
  out = StreamController<T>(
    onListen: () {
      unawaited(
        ready.then((_) {
          if (cancelled) return;
          inner = start().listen(
            out.add,
            onError: out.addError,
            onDone: out.close,
          );
        }),
      );
    },
    onCancel: () {
      cancelled = true;
      return inner?.cancel();
    },
  );
  return out.stream;
}
