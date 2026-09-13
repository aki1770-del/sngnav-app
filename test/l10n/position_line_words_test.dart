/// The words of the line under her map, from what the app measured and never
/// from an exception's text.
///
/// Why this test exists. On 2026-09-14 three rulings met on this one line:
///
/// * A refusal read from text: the line read a refusal out of reason text (「位置情報の許可が拒否
///   されました」) under a map that, from the typed cause, said 現在地不明; and
///   English passed every reason through as written.
/// * No location on this device: on a platform with no location implementation the line named a GPS
///   fault, and in English carried the exception's text, which she would have
///   to decode.
/// * Route setting closed: where route setting is closed, no line may say the route panel
///   works.
///
/// The rules tested here:
///
/// * No refusal is read from text. A refusal's words with no typed cause, and
///   any reason the app's own code did not write, get the no-position line.
/// * Exception text never reaches the line, in either locale.
/// * The type `MissingPluginException`, at any of the stream's platform calls,
///   is known as this device's absence of location, and gets the no-location-on-this-device line.
/// * Reasons the app writes on a path it measured keep their words.
/// * The route-panel sentence follows route setting, and the two ruled lines
///   never carry it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart'
    show LocationPermission, PermissionDeniedException, Position;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

// Ruled bytes, 2026-09-14.
const _noPositionJa = '現在地不明 — 位置を取得できませんでした。地図は表示されたままです。';
const _noPositionEn =
    'Position unknown — this app could not get a position. The map remains.';
const _noLocationHereJa =
    '現在地不明 — この端末では、このアプリは位置を取得できません。地図は表示されたままです。';
const _noLocationHereEn =
    'Position unknown — this app cannot get a position on this device. The map remains.';

const _routeClauseJa = 'ルート欄はタップで引き続き使えます。';
const _routeClauseEn = 'the route panel still works by tap';

const ja = AppL10n(Locale('ja'));
const en = AppL10n(Locale('en'));

/// Reasons the app's own code writes on a path it measured.
const _measured = [
  'Location services disabled',
  'Location service check timed out — platform did not answer',
  'Location permission check timed out — platform did not answer',
  'Location permission request timed out — no answer from the platform dialog',
  'Degraded GPS fix — non-finite coordinate (lat=NaN, lon=1.0, acc=5.0)',
  'GPS stream ended by the platform',
];

MissingPluginException _missing(String method) => MissingPluginException(
    'No implementation found for method $method on channel '
    'flutter.baseflow.com/geolocator');

void main() {
  group('no refusal from text', () {
    test('a refusal\'s words with no typed cause get the ruled line', () {
      for (final reason in const [
        'Location permission denied',
        'Location permission permanently denied — change in OS settings',
      ]) {
        for (final open in const [true, false]) {
          expect(ja.gpsUnavailable(reason, routeSettingOpen: open),
              _noPositionJa, reason: reason);
          expect(en.gpsUnavailable(reason, routeSettingOpen: open),
              _noPositionEn, reason: reason);
        }
      }
    });

    test('a reason the app did not write never reaches the line', () {
      expect(ja.gpsUnavailable('weird novel reason', routeSettingOpen: true),
          _noPositionJa);
      expect(en.gpsUnavailable('weird novel reason', routeSettingOpen: true),
          _noPositionEn);
    });

    test('CONTROL: measured reasons keep their words, with no English left in '
        'the Japanese line', () {
      for (final reason in _measured) {
        final line = ja.gpsUnavailable(reason, routeSettingOpen: true);
        expect(line, startsWith('GPS を取得できません — '), reason: reason);
        expect(RegExp('[A-Za-z]{3,}').hasMatch(line.replaceAll('GPS', '')),
            isFalse,
            reason: 'English leaked into 「$line」');
        expect(en.gpsUnavailable(reason, routeSettingOpen: true),
            'GPS unavailable — $reason. The map remains; $_routeClauseEn.');
      }
    });
  });

  group('exception text never reaches the line', () {
    const tail =
        "MissingPluginException(No implementation found) PERMISSION_DENIED boom";

    test('a stream error keeps its wrapper words and loses the tail', () {
      final j = ja.gpsUnavailable('GPS stream error: $tail', routeSettingOpen: true);
      final e = en.gpsUnavailable('GPS stream error: $tail', routeSettingOpen: true);
      expect(j, contains('GPSストリームのエラー'));
      expect(e,
          'GPS unavailable — GPS stream error. The map remains; $_routeClauseEn.');
      for (final line in [j, e]) {
        expect(line, isNot(contains('MissingPlugin')), reason: line);
        expect(line, isNot(contains('PERMISSION')), reason: line);
        expect(line, isNot(contains('boom')), reason: line);
      }
    });

    test('an exception while starting, of an untyped kind, gets the no-position line',
        () {
      expect(ja.gpsUnavailable('GPS init error: $tail', routeSettingOpen: true),
          _noPositionJa);
      expect(en.gpsUnavailable('GPS init error: $tail', routeSettingOpen: true),
          _noPositionEn);
    });

    test('the typed absence\'s line is the ruled bytes', () {
      expect(ja.noLocationOnThisDeviceStatus, _noLocationHereJa);
      expect(en.noLocationOnThisDeviceStatus, _noLocationHereEn);
    });
  });

  group('the route-panel sentence follows route setting', () {
    test('open: the measured-reason and refusal lines carry it', () {
      expect(ja.gpsUnavailable(_measured.first, routeSettingOpen: true),
          endsWith(_routeClauseJa));
      expect(ja.locationOffStatus(permanently: false, routeSettingOpen: true),
          endsWith(_routeClauseJa));
      expect(ja.locationOffStatus(permanently: true, routeSettingOpen: true),
          endsWith(_routeClauseJa));
      expect(en.locationOffStatus(permanently: false, routeSettingOpen: true),
          endsWith('$_routeClauseEn.'));
    });

    test('closed: no line carries it, and the rest is unchanged', () {
      for (final permanently in const [false, true]) {
        final jOpen =
            ja.locationOffStatus(permanently: permanently, routeSettingOpen: true);
        final jClosed = ja.locationOffStatus(
            permanently: permanently, routeSettingOpen: false);
        expect(jClosed, jOpen.replaceAll(_routeClauseJa, ''));
        final eOpen =
            en.locationOffStatus(permanently: permanently, routeSettingOpen: true);
        final eClosed = en.locationOffStatus(
            permanently: permanently, routeSettingOpen: false);
        expect(eClosed, eOpen.replaceAll('; $_routeClauseEn.', '.'));
      }
      for (final reason in _measured) {
        expect(ja.gpsUnavailable(reason, routeSettingOpen: false),
            isNot(contains('ルート欄')));
        expect(en.gpsUnavailable(reason, routeSettingOpen: false),
            'GPS unavailable — $reason. The map remains.');
      }
    });

    test('the two ruled lines never carry it', () {
      for (final l in const [ja, en]) {
        expect(l.noLocationOnThisDeviceStatus, isNot(contains('ルート欄')));
        expect(l.noLocationOnThisDeviceStatus, isNot(contains('route panel')));
        expect(l.gpsUnavailable('x', routeSettingOpen: true),
            isNot(contains('ルート欄')));
        expect(l.gpsUnavailable('x', routeSettingOpen: true),
            isNot(contains('route panel')));
      }
    });
  });

  group('the stream types what it measured', () {
    Stream<PositionFix> missingAt(String call) => herPositionStream(
          isServiceEnabled: call == 'isServiceEnabled'
              ? () async => throw _missing('isLocationServiceEnabled')
              : () async => true,
          checkPermission: call == 'checkPermission'
              ? () async => throw _missing('checkPermission')
              : () async => call == 'requestPermission'
                  ? LocationPermission.denied
                  : LocationPermission.whileInUse,
          requestPermission: call == 'requestPermission'
              ? () async => throw _missing('requestPermission')
              : () async => LocationPermission.whileInUse,
          positionStream: switch (call) {
            'positionStream-throws' => () => throw _missing('getPositionStream'),
            'positionStream-errors' => () =>
                Stream<Position>.error(_missing('getPositionStream')),
            _ => () => const Stream<Position>.empty(),
          },
        );

    for (final call in const [
      'isServiceEnabled',
      'checkPermission',
      'requestPermission',
      'positionStream-throws',
      'positionStream-errors',
    ]) {
      test('$call: MissingPluginException is this device\'s absence, by type',
          () async {
        final e = await missingAt(call).first.timeout(const Duration(seconds: 2));
        expect(isNoLocationOnThisDevice(e), isTrue, reason: '$e');
        expect(isLocationRefusal(e), isFalse);
      });
    }

    test('CONTROL: an exception whose text names a missing plugin is not typed',
        () async {
      final e = await herPositionStream(
        isServiceEnabled: () async =>
            throw Exception('MissingPluginException(No implementation found)'),
      ).first;
      expect(isNoLocationOnThisDevice(e), isFalse);
      expect(isLocationRefusal(e), isFalse);
    });

    test('a denial sent when the stream subscribes is typed, and logged as such',
        () async {
      final e = await herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        positionStream: () => Stream<Position>.error(
            const PermissionDeniedException('denied at subscribe')),
      ).first;
      expect(isLocationRefusal(e), isTrue);
      expect(isNoLocationOnThisDevice(e), isFalse);
      expect((e as PositionUnavailable).reason,
          contains('when the position stream subscribed'),
          reason: 'the log can tell this denial from the dialog\'s');
    });
  });
}
