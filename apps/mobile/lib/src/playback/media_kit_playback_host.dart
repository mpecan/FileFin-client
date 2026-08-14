import 'package:filefin_mobile/src/playback/ca_bundle.dart';
import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// libmpv's two synthetic track ids, which are not tracks.
///
/// `media_kit` prepends `auto` and `no` to every list it reports. They are
/// mpv's own "pick for me" and "none" pseudo-entries, not things the file
/// contains: showing them in an audio menu would offer a user two options that
/// look like languages and are not, and "1 audio track" would read as three.
const _syntheticTrackIds = {'auto', 'no'};

/// Translates between this app's playback vocabulary and `media_kit`'s.
///
/// **One of exactly two files allowed to import `package:media_kit`**
/// (`app_no_raw_http`). Everything here is translation over an injected
/// [MpvPlayer], which is what lets the whole file be tested against
/// `FakeMpvPlayer` with no libmpv present, and then again against a real one.
final class MediaKitPlaybackHost extends PlaybackHost {
  /// Wraps one [MpvPlayer].
  MediaKitPlaybackHost(this._player);

  final MpvPlayer _player;

  @override
  Stream<Duration> get position => _player.position;

  @override
  Stream<Duration> get duration => _player.duration;

  @override
  Stream<bool> get playing => _player.playing;

  @override
  Stream<bool> get completed => _player.completed;

  @override
  Stream<PlaybackTracks> get tracks => _player.tracks.map(_translateTracks);

  @override
  Stream<String> get errors => _player.errors;

  /// Loads [request], headers and start position included.
  ///
  /// `tls-verify` is set **before** the open, being a property of the
  /// connection mpv is about to make. libmpv verifies nothing by default
  /// (`docs/field-notes.md`), so this is the only thing between an OS-trusted
  /// server and an unverified peer; D10 covers what it cannot help with.
  ///
  /// `Media`'s `start:` rather than open-then-seek: mpv applies it as `start=`
  /// on load, so playback begins at the resume position rather than showing a
  /// second of the beginning first.
  @override
  Future<void> open(PlaybackRequest request) async {
    // On Android, mpv uses mbedTLS or GnuTLS, neither of which knows where
    // the system trust store is. The device's live CA certificates (system
    // AND user-installed) are exported to a PEM file at startup by
    // `CaBundle`; handing that to mpv as `tls-ca-file` gives it the same
    // trust store the platform HTTP stack uses, and `tls-verify=yes` then
    // verifies against the device's actual roots rather than a bundled
    // snapshot. On every other platform the system libmpv uses the OS trust
    // store natively.
    final caPath = await CaBundle.path;
    if (caPath != null) {
      await _player.setProperty('tls-ca-file', caPath);
    }
    await _player.setProperty('tls-verify', request.verifyTls ? 'yes' : 'no');
    await _player.open(
      Media(
        request.url.toString(),
        httpHeaders: request.headers,
        start: request.startAt,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// Volume, `0.0`–`1.0` here and **0–100** to libmpv.
  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 1) * 100);

  /// Switches to [track] by the id libmpv itself reported.
  ///
  /// `AudioTrack`'s positional arguments are `(id, title, language)` — read off
  /// `media_kit`'s own `track.dart:152`, and not the order the names suggest.
  /// Passing them the other way round put the label in `language`, which the
  /// tests caught only because they assert the fields rather than the count.
  @override
  Future<void> selectAudioTrack(PlaybackTrackRef track) =>
      _player.setAudioTrack(AudioTrack(track.id, track.label, null));

  /// Shows [source]'s **text**, or turns subtitles off.
  ///
  /// `SubtitleTrack.data`, deliberately not `SubtitleTrack.uri`. The sidecar
  /// route is authenticated, so fetching it through `LibraryApi` gets the
  /// cookie jar, F3's retry and F15's pin; a `sub-add` would use libmpv's own
  /// unverified HTTP with none of the three. Measured working at M4.0/E4: the
  /// server's `text/vtt` body handed straight to `SubtitleTrack.data` produced
  /// a rendered cue.
  @override
  Future<void> selectSubtitleTrack(SubtitleSource? source) =>
      _player.setSubtitleTrack(
        source == null
            ? SubtitleTrack.no()
            : SubtitleTrack.data(
                source.data,
                title: source.label,
                language: source.label,
              ),
      );

  @override
  Widget buildSurface() => _player.buildSurface();

  @override
  Future<void> dispose() => _player.dispose();

  /// Drops the synthetic entries and labels what is left.
  ///
  /// A track's `language` is what a person recognises; `title` is often absent
  /// and the id is a number. Falling back through language → title → codec →
  /// id means the menu always says *something*, which matters because a file
  /// with two unnamed tracks is common and "Track 1 / Track 2" is still usable
  /// where two blank rows are not.
  static PlaybackTracks _translateTracks(Tracks tracks) => PlaybackTracks(
    audio: [
      for (final track in tracks.audio)
        if (!_syntheticTrackIds.contains(track.id))
          PlaybackTrackRef(id: track.id, label: _labelFor(track)),
    ],
  );

  static String _labelFor(AudioTrack track) {
    final language = track.language;
    if (language != null && language.isNotEmpty) return language;
    final title = track.title;
    if (title != null && title.isNotEmpty) return title;
    final codec = track.codec;
    if (codec != null && codec.isNotEmpty) return '$codec (${track.id})';
    return 'Track ${track.id}';
  }
}
