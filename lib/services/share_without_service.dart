/// A share that runs WITHOUT its foreground service: when it ends, and what the
/// app says.
///
/// WHY (ruled 2026-10-06 by a safety review, audited, and amended the same day).
/// The app starts the drive's foreground service only when it can post her a
/// notification. That needs the Android 13 permission AND notifications switched
/// on for the app, which can be off at any API level. A slow or failed read also
/// counts as "cannot post". Without the service, the share's fixes stop as soon
/// as the app is no longer visible: Android throttles a background app's
/// location, and the location plugin stops the stream outright when the activity
/// detaches. The app read that silence as a GPS loss and told her the stop line
/// for a fault that was not there, while the warnings she believed were running
/// were not.
///
/// THE RULE, on this branch only (a share WITH its service is untouched by any
/// lifecycle state):
///   - when the app LEAVES the screen (the transition into hidden from
///     inactive; a return from paused also reports hidden on its way back,
///     and that is not a leave), the share ENDS, and she is told once, by
///     voice and vibration, with the line below. Nothing repeats; on her
///     return the page shows the share as not running, with a notice;
///   - never before the platform stream has subscribed: a permission screen at
///     the share's own start is not "leaving";
///   - at the moment it subscribes, a report of hidden or paused may be stale:
///     her answer to a full-screen permission screen can arrive before her
///     return to the app is reported. So it starts a settle window
///     [kShareAwaySettle] on its own timer. A report of inactive or resumed
///     inside it cancels it and nothing is told (the line would be false as
///     she comes back to her own share); if she is still away when it ends,
///     the rule fires then. A share found to have no service by a failure
///     before its first fix goes through the same window, since that failure
///     can arrive at the same instant. A leave in the middle of a share fires
///     on the change itself;
///   - `inactive` (the shade pulled down, a dialog, a call's heads-up, an
///     unfocused split-screen window) changes nothing: the app is on screen, the
///     line would be false, and the GPS-loss reading runs exactly as in front.
///     Suppressing it there would withdraw a real warning without telling her;
///   - while it runs, the share's row carries [AppL10n.shareWithoutServiceDisclosure]
///     in place of the drive-continues words, which are false on this branch.
///
/// WHICH LINES SPEAK THROUGH A REFUSED AUDIO FOCUS (a classification, written
/// down so that it is decided, not inherited by whatever reaches the player):
///   - every hazard line in the offline catalog: an existing decision, not
///     reopened here (MainActivity.kt, "DENIAL does not gate a safety phrase");
///   - the line below, [kShareStoppedAppLeftJaSpokenText], also speaks through a
///     refusal, including over a phone call. It is a status line, and under the
///     dignity principle that the machine yields to the person it need not. It
///     does so for now because on this branch the app cannot post a
///     notification: once she is away, nothing else can carry the words, and
///     withholding them would leave a vibration with no content until she
///     returns. Its cost is one spoken line, about 4.7 s, over her call, once
///     per leave. Yielding (the vibration now and the words when she is back in
///     front, and not counted as told until then) needs the bundled player to
///     report "withheld" without falling back to the phone's own voice. That is
///     a change to the voice lane, and the design is open with the dignity
///     review.
library;

/// The settle window at the share's subscription (see the rule above).
/// PROVISIONAL: 2 s is a chosen margin, not a measurement; a device read of
/// the gap between a permission answer and the return to the app replaces it.
/// It must stay below the drought bound less one second (kPositionDrought in
/// lib/route_act.dart), so no GPS-loss reading can fall inside it; a test
/// holds that.
const Duration kShareAwaySettle = Duration(seconds: 2);

/// Told once when a share without its service ends because the app left the
/// screen. The exact string is the offline voice catalog's lookup key
/// (lib/voice/offline_safety_voice.dart, 'share_stopped_app_left'), so it must
/// not drift by a byte.
const String kShareStoppedAppLeftJaSpokenText =
    'アプリが画面から離れたため、現在地の警告は止まりました。';

/// English twin of [kShareStoppedAppLeftJaSpokenText].
const String kShareStoppedAppLeftEnSpokenText =
    'Because the app left the screen, warnings for your location have stopped.';
