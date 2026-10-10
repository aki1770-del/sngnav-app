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
///   - the line below, [kShareStoppedAppLeftJaSpokenText], also SPEAKS THROUGH a
///     refusal, including over a phone call. Decided 2026-10-06 by the safety
///     review (AAA, r122_build_call_and_preshare_ruling_2026_10_06.md section
///     1, which withdrew its own earlier "need not" the same day) with the
///     dignity review, not inherited. On this branch the share is over once she
///     is away, and the app cannot post a notification, so nothing else can
///     carry the words: withholding them would leave her a vibration with no
///     content until she reopens the app, which may be never on that drive.
///     Whether she would be told at all is ambiguous, and that ambiguity routes
///     toward telling her now; one line of about 4.7 s over her call is the
///     cheaper halt. Its manner: once per leave, ducked, as navigation
///     guidance; told means handed to the player, never heard; the notice on
///     her return stays the backstop. Its condition: the cannot-post words, and
///     the half of the not-known-yet words for a drive without notifications,
///     tell her before her yes that the app says so once, even during a call.
///     It reopens on the same terms as the line after it, and a yield design
///     then meets the same floor;
///   - the stop confirmation (AppL10n.shareEndedSpokenLine, told at 停止,
///     main.dart _tellShareEnded) also SPEAKS THROUGH a refusal, including
///     over a call. Decided 2026-10-10 by the safety review (AAA bb2d2937,
///     section 3) and the dignity review (WDA 46e240b2, section 2), not
///     inherited. The app cannot tell a meant 停止 from one she did not mean,
///     and the line exists for the second. A line deferred to the end of the
///     call would leave her, for the call, with one pulse nothing has taught
///     her. And nothing built can yield honestly today: the bundled player
///     discards the focus answer. Its manner: once per end, ducked, as
///     navigation guidance; told means handed to the player, never heard. Its
///     condition, as the line before it rests on the call words: the can-post
///     words tell her, before her yes, that 停止 is said once even during a
///     call (AppL10n.driveDisclosure). It reopens only when the ended pulse is
///     taught somewhere she will meet it AND the bundled player can report
///     "withheld" without falling back to the phone's own voice; a yield
///     design then meets the safety review's floor (not told until spoken; the
///     pulse alone is never told; spoken when the call releases focus; yields
///     only during a call).
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
