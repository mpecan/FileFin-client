#!/usr/bin/env bash
# E-6 / R3 — does libmpv keep decoding when the process is backgrounded, and
# what has to be true for the OS to keep the sound on? (docs/risks.md R3, F14)
#
# The app under test is a SCRATCH app generated into a temp directory, never
# `apps/mobile` — CLAUDE.md §1 keeps speculative code out of the tree, and the
# arms below deliberately include configurations we would not ship.
#
# The instrument is one line per second from the Dart side:
#     TICK wall=<ms since start> pos=<ms> playing=<bool> life=<lifecycle>
# `pos` advancing while `life=paused` means libmpv decoded in the background.
# That is a claim about DECODING. Whether the OS then let the sound out is a
# separate question, and on Android it is read from `dumpsys audio`'s
# `mutedState`, which is the field that answers it.
#
# Arms (each is a separate build, because two of the three variables are
# build-time):
#
#   android-bare       nothing configured
#   android-service    audio_service: a MediaSession and a foreground service
#   ios-bare           no UIBackgroundModes
#   ios-plist          UIBackgroundModes: audio, nothing else
#
# Every arm sets `pauseUponEnteringBackgroundMode: false` on `Video`, because
# `media_kit_video`'s DEFAULT for that argument is `true` and it pauses the
# player itself on `AppLifecycleState.paused`
# (media_kit_video-2.0.1/lib/src/video/video_texture.dart:281-299). With the
# default left alone every arm reads "playback stops when backgrounded" and the
# reason is a widget argument rather than anything the OS did. That is the
# negative control for the whole spike and it is arm `android-bare-pausebg`.
#
# Usage:
#   tool/spikes/e6_background_playback.sh android-bare
#   tool/spikes/e6_background_playback.sh android-bare-pausebg
#   tool/spikes/e6_background_playback.sh android-service
#   tool/spikes/e6_background_playback.sh ios-bare        [simulator udid]
#   tool/spikes/e6_background_playback.sh ios-plist       [simulator udid]
#
# Prerequisites: the Flutter SDK on PATH, ffmpeg, and — per arm — an attached
# Android device/emulator (adb) or a booted iOS simulator (xcrun simctl).
#
# THE IOS SIMULATOR CANNOT ANSWER THE AUDIO HALF, and the reason is in the
# shipped binary rather than in this script. media_kit_libs_ios_video 1.1.4
# builds libmpv twice, and the two builds differ in exactly the field that
# matters:
#   ios-arm64 (device)   -Daudiounit=enabled
#   ios-arm64_x86_64-simulator  -Daudiounit=disabled -Dcoreaudio=disabled
# So on the simulator there is no audio output compiled in at all and playback
# runs off the video clock. The simulator arms below establish whether the
# PROCESS is suspended; `docs/verification-backlog.md` carries the audio half.
set -uo pipefail

ARM="${1:-}"
[ -n "$ARM" ] || { echo "usage: $0 <arm> [simulator-udid]"; exit 2; }
SIM_UDID="${2:-booted}"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
PKG=dev.filefin.spike.e6
WORK="${FILEFIN_E6_DIR:-${TMPDIR:-/tmp}/filefin-e6}"

command -v flutter >/dev/null 2>&1 || { echo "FATAL: flutter not on PATH"; exit 2; }
command -v ffmpeg  >/dev/null 2>&1 || { echo "FATAL: ffmpeg not on PATH"; exit 2; }

# --- the scratch app --------------------------------------------------------
if [ ! -d "$WORK/e6" ]; then
  mkdir -p "$WORK"
  ( cd "$WORK" && flutter create --platforms=android,ios --org dev.filefin.spike e6 >/dev/null )
  ( cd "$WORK/e6" \
    && flutter pub add media_kit:1.2.6 media_kit_video:2.0.1 \
         media_kit_libs_android_video:1.3.8 media_kit_libs_ios_video:1.1.4 \
         audio_service:0.18.19 >/dev/null )
fi
APP="$WORK/e6"
mkdir -p "$APP/assets"
# Five minutes, so a 60 s background window cannot be confused with the file
# simply ending.
[ -f "$APP/assets/clip.mp4" ] || ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc=size=640x360:rate=25:duration=300" \
  -f lavfi -i "sine=frequency=440:duration=300" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$APP/assets/clip.mp4"

cat > "$APP/lib/main.dart" <<'DART'
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

SpikeHandler? _handler;
const arm = String.fromEnvironment('ARM', defaultValue: 'bare');
const pauseOnBackground = bool.fromEnvironment('PAUSEBG');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  print('E6 arm=$arm pausebg=$pauseOnBackground');
  if (arm == 'service') {
    _handler = await AudioService.init(
      builder: SpikeHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.filefin.spike.audio',
        androidNotificationChannelName: 'Spike playback',
        androidNotificationOngoing: true,
      ),
    );
  }
  runApp(const SpikeApp());
}

class SpikeHandler extends BaseAudioHandler {
  @override
  Future<void> play() async {
    print('E6 REMOTE play');
    await SpikeApp.player?.play();
  }

  @override
  Future<void> pause() async {
    print('E6 REMOTE pause');
    await SpikeApp.player?.pause();
  }
}

class SpikeApp extends StatefulWidget {
  const SpikeApp({super.key});
  static Player? player;
  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> with WidgetsBindingObserver {
  final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final Stopwatch _wall = Stopwatch()..start();
  Duration _pos = Duration.zero;
  bool _playing = false;
  String _life = 'resumed';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SpikeApp.player = _player;
    _player.stream.position.listen((p) => _pos = p);
    _player.stream.playing.listen((p) => _playing = p);
    unawaited(_player.open(Media('asset:///assets/clip.mp4')));
    Timer.periodic(const Duration(seconds: 1), (_) {
      print('TICK wall=${_wall.elapsedMilliseconds} pos=${_pos.inMilliseconds} '
          'playing=$_playing life=$_life');
    });
    if (arm == 'service') {
      _handler?.mediaItem.add(const MediaItem(
          id: 'spike', title: 'E-6 spike clip', album: 'FileFin'));
      _handler?.playbackState.add(PlaybackState(
          controls: [MediaControl.pause],
          playing: true,
          processingState: AudioProcessingState.ready));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _life = state.name;
    print('E6 LIFECYCLE ${state.name}');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Video(
            controller: _controller,
            pauseUponEnteringBackgroundMode: pauseOnBackground,
          ),
        ),
      );
}
DART

python3 - "$APP/pubspec.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if 'assets/clip.mp4' not in s:
    s = s.replace('  uses-material-design: true\n',
                  '  uses-material-design: true\n  assets:\n    - assets/clip.mp4\n')
open(p, 'w').write(s)
PY

android_manifest() {
  python3 - "$APP/android/app/src/main/AndroidManifest.xml" "$1" <<'PY'
import sys
p, want = sys.argv[1], sys.argv[2] == 'service'
s = open(p).read()
s = s.replace('android:name="com.ryanheise.audioservice.AudioServiceActivity"',
              'android:name=".MainActivity"')
import re
s = re.sub(r'\n *<uses-permission android:name="android\.permission\.(FOREGROUND_SERVICE|FOREGROUND_SERVICE_MEDIA_PLAYBACK|WAKE_LOCK|POST_NOTIFICATIONS)"/>', '', s)
s = re.sub(r'\n *<service android:name="com\.ryanheise\.audioservice\.AudioService".*?</receiver>', '', s, flags=re.S)
if want:
    s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
'''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>''')
    s = s.replace('android:name=".MainActivity"',
                  'android:name="com.ryanheise.audioservice.AudioServiceActivity"')
    s = s.replace('''        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />''','''        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback" android:exported="true">
            <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
        </receiver>''')
open(p, 'w').write(s)
PY
}

ios_plist() {
  python3 - "$APP/ios/Runner/Info.plist" "$1" <<'PY'
import re, sys
p, want = sys.argv[1], sys.argv[2] == 'yes'
s = open(p).read()
s = re.sub(r'\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n', '', s)
if want:
    s = s.replace('</dict>\n</plist>',
                  '\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n</dict>\n</plist>')
open(p, 'w').write(s)
PY
}

run_android() {
  local dartarm="$1" pausebg="$2" activity="$3"
  ( cd "$APP" && flutter build apk --debug \
      --dart-define=ARM="$dartarm" --dart-define=PAUSEBG="$pausebg" ) || return 1
  "$ADB" install -r -g "$APP/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
  "$ADB" logcat -c
  "$ADB" logcat -v time flutter:I '*:S' > "$WORK/android.log" &
  local logpid=$!
  "$ADB" shell am start -S -n "$PKG/$activity" >/dev/null
  sleep 20
  echo "--- FOREGROUND, from dumpsys audio ---"
  "$ADB" shell dumpsys audio | grep 'OpenSL' | grep -o 'state:[a-z]*.*mutedState:[a-z]*' | tail -1
  "$ADB" shell input keyevent KEYCODE_HOME
  sleep 60
  echo "--- BACKGROUNDED, from dumpsys audio ---"
  "$ADB" shell dumpsys audio | grep 'OpenSL' | grep -o 'state:[a-z]*.*mutedState:[a-z]*' | tail -1
  kill "$logpid" 2>/dev/null
  echo "--- ticks, every fifth ---"
  grep -o 'TICK.*' "$WORK/android.log" | awk 'NR%5==1'
}

run_ios_sim() {
  local dartarm="$1"
  ( cd "$APP" && flutter build ios --debug --simulator \
      --dart-define=ARM="$dartarm" --dart-define=PAUSEBG=false ) || return 1
  xcrun simctl terminate "$SIM_UDID" "$PKG" >/dev/null 2>&1
  xcrun simctl uninstall "$SIM_UDID" "$PKG" >/dev/null 2>&1
  xcrun simctl install "$SIM_UDID" "$APP/build/ios/iphonesimulator/Runner.app"
  pkill -f 'log stream --style compact' 2>/dev/null
  ( xcrun simctl spawn "$SIM_UDID" log stream --style compact \
      --predicate 'processImagePath CONTAINS "Runner"' > "$WORK/ios.log" 2>&1 & )
  sleep 3
  xcrun simctl launch "$SIM_UDID" "$PKG" >/dev/null
  sleep 20
  # Foregrounding another app is how a simulator gets backgrounded from a
  # script; there is no `simctl home`.
  xcrun simctl launch "$SIM_UDID" com.apple.Preferences >/dev/null
  sleep 60
  pkill -f 'log stream --style compact' 2>/dev/null
  echo "--- ticks, every fifth ---"
  grep -o 'TICK.*' "$WORK/ios.log" | awk 'NR%5==1'
  echo "--- last three lines ---"
  grep -oE 'TICK.*|E6 LIFECYCLE.*' "$WORK/ios.log" | tail -3
}

case "$ARM" in
  android-bare)
    android_manifest bare; run_android bare false .MainActivity ;;
  android-bare-pausebg)
    android_manifest bare; run_android bare true .MainActivity ;;
  android-service)
    android_manifest service
    run_android service false com.ryanheise.audioservice.AudioServiceActivity
    echo "--- MediaSession ---"
    "$ADB" shell dumpsys media_session | grep -E "package=$PKG|state=PlaybackState|metadata:" | head -3
    echo "--- a hardware media key, routed back to Dart ---"
    "$ADB" logcat -c
    "$ADB" logcat -v time flutter:I '*:S' > "$WORK/remote.log" &
    remote=$!
    sleep 2; "$ADB" shell input keyevent KEYCODE_MEDIA_PAUSE; sleep 4
    kill "$remote" 2>/dev/null
    grep -o 'E6 REMOTE.*' "$WORK/remote.log" || echo "NO REMOTE COMMAND REACHED DART"
    ;;
  ios-bare)  ios_plist no;  run_ios_sim bare ;;
  ios-plist) ios_plist yes; run_ios_sim bare ;;
  *) echo "unknown arm: $ARM"; exit 2 ;;
esac
