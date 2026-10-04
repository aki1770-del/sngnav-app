/// The phrases (文節) of every Japanese line the next-turn banner draws,
/// PINNED here, apart from lib/, so that a test can hold the app's own lists to
/// them and judge where a line breaks without asking the app.
///
/// A line on the banner may break where its sentence already has a space, and
/// between two phrases; never inside a phrase. The lines are the app's words
/// byte for byte: joining a list gives the line she hears and reads.
library;

/// Every maneuver type the localizer names, and one it does not ('other',
/// which it calls 次の案内). 19 types.
const List<String> kManeuverTypes = [
  'depart', 'arrive', 'straight', //
  'left', 'slight_left', 'sharp_left',
  'right', 'slight_right', 'sharp_right',
  'u_turn_left', 'u_turn_right', 'uturn',
  'roundabout_enter', 'roundabout', 'rotary',
  'merge', 'ramp_left', 'ramp_right',
  'other',
];

const Map<String, String> _nounJa = {
  'left': '左折',
  'slight_left': '斜め左方向',
  'sharp_left': '左への急カーブ',
  'right': '右折',
  'slight_right': '斜め右方向',
  'sharp_right': '右への急カーブ',
  'straight': '直進',
  'u_turn_left': 'Uターン',
  'u_turn_right': 'Uターン',
  'uturn': 'Uターン',
  'roundabout_enter': 'ロータリー',
  'roundabout': 'ロータリー',
  'rotary': 'ロータリー',
  'merge': '合流',
  'ramp_left': '左のランプ',
  'ramp_right': '右のランプ',
};

/// Her line for a turn of [type]: read as given, or with a check when
/// [hedged]; with the icy sentence when [icy].
List<String> herLinePhrasesSpec(
  String type, {
  required bool hedged,
  required bool icy,
}) {
  final noun = _nounJa[type] ?? '次の案内';
  final List<String> line;
  if (!hedged) {
    line = switch (type) {
      'depart' => ['ルート案内を', '開始します。'],
      'arrive' => ['まもなく', '目的地です。'],
      'straight' => ['このまま', '直進します。'],
      _ => ['この先、', '$noun ', 'です。'],
    };
  } else if (type == 'arrive') {
    line = [
      '現在地が', '不確かですが、', 'まもなく', '目的地の', '付近です。', //
      '位置を', 'ご確認ください。',
    ];
  } else {
    line = [
      '現在地が', '不確かです。', 'この先 ', '$noun ', 'の可能性が', //
      'ありますが、', '位置を', 'ご確認のうえ', 'ご判断ください。',
    ];
  }
  if (!icy) return line;
  return [
    ...line.sublist(0, line.length - 1),
    '${line.last} ',
    'この曲がり角は', '路面が', '凍結している', '可能性が', 'あります。', //
  ];
}

/// The banner's own lines: the three states, the paused line, the icy mark
/// and the two lines that say where the icy mark came from.
const Map<String, List<String>> kPanelPhrasesSpec = {
  'そのまま読み上げます': ['そのまま', '読み上げます'],
  '確認をお願いして読み上げます': ['確認を', 'お願いして', '読み上げます'],
  '読み上げません': ['読み上げません'],
  'この曲がり角の案内は保留しています（現在地が信頼できません）。': [
    'この曲がり角の', '案内は', '保留しています', '（現在地が', '信頼できません）。', //
  ],
  '❄ 凍結のおそれ': ['❄ ', '凍結のおそれ'],
  '凍結の表示はテスト値です（路面は測定していません）': [
    '凍結の', '表示は', 'テスト値です', '（路面は', '測定していません）', //
  ],
  '凍結の表示は気象庁の気温・湿度からの推定です（路面は測定していません）': [
    '凍結の', '表示は', '気象庁の', '気温・湿度からの', '推定です', '（路面は', //
    '測定していません）',
  ],
};

/// U+2060 WORD JOINER, written here rather than imported, so that this spec
/// and the tests built on it do not depend on the code they judge.
const String kSpecWordJoiner = '⁠';

/// The offsets in the plain line at which a new line may begin.
Set<int> phraseBoundaries(List<String> phrases) {
  final out = <int>{};
  var at = 0;
  for (final p in phrases) {
    at += p.length;
    out.add(at);
  }
  return out..remove(at);
}

/// [phrases] with a word joiner between the characters of each phrase.
String joinedSpec(List<String> phrases) => [
      for (final p in phrases) p.split('').join(kSpecWordJoiner),
    ].join();
