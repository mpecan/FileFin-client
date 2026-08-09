import 'package:filefin_mobile/src/browse/media_detail_page.dart'
    show humanSize;
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';

/// The sizes the metered prompt can be set to fire above (F13).
///
/// The current value is unioned in by [PlaybackSettingsSheet] rather than
/// assumed to be one of these: `settings.json` is hand-editable and a
/// `DropdownButton` whose `value` is not among its items throws.
/// **All four are powers of 1000**, matching the kB/MB/GB `humanSize` writes on
/// them and matching `PlaybackPrefs`' own default. Three of them were powers of
/// 1024 until M4.R/P7, mixed in with one that was not, so the list a person
/// chose from read "100 MB, 477 MB, 1.0 GB, 4.0 GB" — one entry rendered from a
/// different base than its neighbours and none of them the round number it
/// claimed to be.
const meteredWarnChoices = <int>[
  100 * 1000 * 1000,
  500 * 1000 * 1000,
  1000 * 1000 * 1000,
  4 * 1000 * 1000 * 1000,
];

/// The reporting intervals, in **media** seconds. 30 is upstream's own.
const progressIntervalChoices = <int>[10, 30, 60, 120];

/// SPEC §7's playback settings, per server and not.
///
/// **This sheet is why `Refuse(wifiOnlyOnMetered)` and D10's refusal are
/// reachable at all.** Both are decided by fields on [SavedServer], and until
/// M4.8 nothing in a running app could set either — a settings field nobody can
/// write is §5's dead branch wearing §1's clothes.
///
/// It edits a copy and reports every change through [onChanged], rather than
/// owning a `SettingsStore`: the write can fail (a full disk, a revoked
/// permission) and the screen that has somewhere to show that failure is the
/// one that opened this.
class PlaybackSettingsSheet extends StatefulWidget {
  /// Edits [server]'s playback settings and the shared [prefs].
  const PlaybackSettingsSheet({
    required this.server,
    required this.prefs,
    required this.onChanged,
    super.key,
  });

  /// The server whose per-server settings these are.
  final SavedServer server;

  /// The settings that are not per server.
  final PlaybackPrefs prefs;

  /// Called with the whole new state on every change.
  final void Function(SavedServer server, PlaybackPrefs prefs) onChanged;

  @override
  State<PlaybackSettingsSheet> createState() => _PlaybackSettingsSheetState();
}

class _PlaybackSettingsSheetState extends State<PlaybackSettingsSheet> {
  late SavedServer _server = widget.server;
  late PlaybackPrefs _prefs = widget.prefs;

  void _apply({SavedServer? server, PlaybackPrefs? prefs}) {
    setState(() {
      _server = server ?? _server;
      _prefs = prefs ?? _prefs;
    });
    widget.onChanged(_server, _prefs);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Playback on ${_server.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SwitchListTile(
            key: const Key('wifiOnly'),
            value: _server.wifiOnly,
            onChanged: (on) => _apply(server: _server.copyWith(wifiOnly: on)),
            title: const Text('Wi-Fi only'),
            subtitle: const Text(
              'Refuse to play at all on a metered connection, instead of '
              'asking about large files.',
            ),
          ),
          SwitchListTile(
            key: const Key('allowUnverifiedPlayback'),
            value: _server.allowUnverifiedPlayback,
            onChanged: (on) =>
                _apply(server: _server.copyWith(allowUnverifiedPlayback: on)),
            title: const Text('Play over an unverified certificate'),
            // D10's cost, named rather than summarised as "less secure". The
            // banner is mentioned here because it is part of what is being
            // agreed to: it stays on screen for the whole of every file.
            subtitle: const Text(
              'This server uses a certificate only this app trusts, and the '
              'player cannot check it. Turning this on sends the session '
              'cookie to a peer whose certificate was never checked, and a '
              'warning banner stays on screen the whole time you are playing.',
            ),
          ),
          _ChoiceRow(
            fieldKey: const Key('meteredWarnBytes'),
            title: 'Ask before playing above',
            subtitle: 'Only on a metered connection (F13).',
            value: _prefs.meteredWarnBytes,
            choices: meteredWarnChoices,
            label: humanSize,
            onChanged: (bytes) =>
                _apply(prefs: _prefs.copyWith(meteredWarnBytes: bytes)),
          ),
          _ChoiceRow(
            fieldKey: const Key('progressIntervalSecs'),
            title: 'Save progress every',
            // The unit is the thing people get wrong about this setting, so it
            // is on screen rather than only in a doc comment: 30 seconds of a
            // paused film is not 30 seconds.
            subtitle:
                'Measured in film time, so a paused film reports nothing.',
            value: _prefs.progressIntervalSecs,
            choices: progressIntervalChoices,
            label: _seconds,
            onChanged: (secs) =>
                _apply(prefs: _prefs.copyWith(progressIntervalSecs: secs)),
          ),
        ],
      ),
    ),
  );

  static String _seconds(int value) => '$value s';
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.fieldKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.choices,
    required this.label,
    required this.onChanged,
  });

  final Key fieldKey;
  final String title;
  final String subtitle;
  final int value;
  final List<int> choices;
  final String Function(int value) label;
  final void Function(int value) onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    // The current value is unioned in and the result sorted, so a settings
    // file holding a number no menu offers is still shown and still editable
    // rather than throwing on the way to being displayed.
    trailing: DropdownButton<int>(
      key: fieldKey,
      value: value,
      onChanged: (picked) => picked == null ? null : onChanged(picked),
      items: [
        for (final choice in {...choices, value}.toList()..sort())
          DropdownMenuItem<int>(value: choice, child: Text(label(choice))),
      ],
    ),
  );
}

/// Opens [PlaybackSettingsSheet] as a modal sheet over [context].
Future<void> showPlaybackSettings(
  BuildContext context, {
  required SavedServer server,
  required PlaybackPrefs prefs,
  required void Function(SavedServer server, PlaybackPrefs prefs) onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => PlaybackSettingsSheet(
    server: server,
    prefs: prefs,
    onChanged: onChanged,
  ),
);
