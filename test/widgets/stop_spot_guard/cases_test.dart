/// The stop-spot guard's named cases (code 16, 2026-10-14): what the sweep
/// files do not say by name.
///
/// - REMOVAL IS NOT A FIX. A fix that removed 共有の同意を取り消す would put
///   現在地を共有 alone in the end slot under 停止, with a yes held, and a
///   double press on 停止 would restart the share he just ended: fail-open
///   (Sakichi Vision 16, "Fail-closed beats fail-open"). The instrument must be
///   red on that tree. Here it is run on code 15's row with the withdrawal
///   removed, built from the same widgets; the same removal applied to the
///   app's own source is a recorded mutant that turns the sweep red.
/// - THE NOTE IS TOLD TO A SCREEN READER. After a withdrawal the note under
///   the control is a live region, so TalkBack announces it when it appears:
///   a sighted driver is told, and a driver who cannot see the screen must be
///   told too. Whether TalkBack speaks it on a device is a device read, not
///   this test.
/// - `end` BEFORE THE SHARE IS CLEARED. His 停止 writes exactly one `end`
///   line for the share, and it is written before the share's stream and
///   number move: written after, the record would hold no `end` at all.
///
/// HONEST BOUND. A test binding, not a phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/d8_stop_spot_guard.dart';

void main() {
  final env = D8Env();
  setUp(env.setUp);
  tearDown(env.tearDown);

  testWidgets(
      'removal is not a fix: on code 15\'s row with the withdrawal removed, '
      'the instrument finds 現在地を共有 under 停止', (tester) async {
    const g = D8Geometry('ja', 2.75, 1.0);
    expect(await d8SetGeometry(tester, g), isTrue, reason: 'a real face');
    var sharing = true;
    late StateSetter set;
    Widget row() => Padding(
          padding: const EdgeInsets.all(32),
          child: StatefulBuilder(builder: (context, s) {
            set = s;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sharing)
                  Row(children: [
                    const Expanded(child: Text('現在地 · ±12 m')),
                    TextButton(
                      key: const Key('stop'),
                      onPressed: () => set(() => sharing = false),
                      child: const Text('停止'),
                    ),
                  ])
                else ...[
                  const Text('位置情報は共有されていません。'),
                  // Code 15's row, end-aligned, with the withdrawal removed.
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(spacing: 8, children: [
                      TextButton(
                        key: const Key('share-location-button'),
                        onPressed: () {},
                        child: const Text('現在地を共有'),
                      ),
                    ]),
                  ),
                ],
              ],
            );
          }),
        );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: row())));
    final from = tester.getRect(find.byKey(const Key('stop')));
    await tester.tapAt(from.center);
    await tester.pump();
    final t = D8Transition('removal', g, from, d8ControlsOnScreen(tester));
    // ignore: avoid_print
    print(t.line());
    expect(t.violations(), isNotEmpty,
        reason: 'the instrument must be red on the removal "fix"');
    expect(
        t.violations().any((v) => v.contains('(share-location-button)')), isTrue,
        reason: 'and it names 現在地を共有, the control that took the end slot');
  });

  testWidgets(
      'the withdrawn note is a live region, so a screen reader is told when it '
      'appears', (tester) async {
    final handle = tester.ensureSemantics();
    const g = D8Geometry('ja', 2.75, 1.0);
    expect(await d8SetGeometry(tester, g), isTrue, reason: 'a real face');
    final app = D8App(env, g);
    await app.launch(tester);
    await app.reveal(tester, app.withdraw);
    await tester.tap(app.withdraw);
    await tester.pump();
    expect(app.withdrawnNote, findsOneWidget, reason: 'control: the note shows');
    final node = tester.getSemantics(app.withdrawnNote);
    final data = node.getSemanticsData();
    expect(data.flagsCollection.isLiveRegion, isTrue,
        reason: 'the note that says her consent was withdrawn is announced '
            'when it appears: a live region');
    expect(data.label, contains(app.l.locationConsentWithdrawnNote),
        reason: 'and the node announced is the note itself, labelled with its '
            'words');
    await app.shares.closeAll();
    handle.dispose();
  });

  testWidgets(
      '停止 writes exactly one `end` for the share, before the share is '
      'cleared', (tester) async {
    const g = D8Geometry('ja', 2.75, 1.0);
    expect(await d8SetGeometry(tester, g), isTrue, reason: 'a real face');
    final app = D8App(env, g);
    await app.launch(tester);
    await app.reveal(tester, app.shareButton);
    await app.tapAndNextFrame(tester, app.shareButton);
    app.shares.current!.add(d8Fix());
    await app.settle(tester);
    final before = app.record.readAll().trimRight().split('\n');
    expect(before.first, 's=1 t=0 k=start a=- v=- late=- fg=1',
        reason: 'control: the share\'s start line is in the record');
    expect(app.endLines(1), 0, reason: 'control: no end while sharing');
    await app.reveal(tester, app.stop);
    await app.tapAndNextFrame(tester, app.stop);
    final after = app.record.readAll().trimRight().split('\n');
    expect(app.endLines(1), 1, reason: 'his 停止 writes exactly one end');
    expect(after.last, 's=1 t=0 k=end',
        reason: 'and it is the last line: nothing of the share follows it');
    expect(app.stop, findsNothing, reason: 'control: the share is cleared');
    await app.settle(tester);
    expect(app.endLines(1), 1, reason: 'still one, once the frames settle');
    await app.shares.closeAll();
  });
}
