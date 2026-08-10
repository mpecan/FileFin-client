import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The plugin's own seam, standing in for Android's `MediaSession` and iOS's
/// now-playing centre.
///
/// Same shape as `_FakePathProvider` in `main_test.dart`, and the same claim:
/// it proves what CROSSED the boundary. What the OS drew is
/// `docs/verification-backlog.md` row N.
class FakeAudioServicePlatform extends AudioServicePlatform
    with MockPlatformInterfaceMixin {
  /// Every call, in order, as `method(detail)`.
  final List<String> calls = [];

  /// The callbacks `AudioService.init` registered, so a test can pretend the
  /// OS pressed a button.
  AudioHandlerCallbacks? callbacks;

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    this.callbacks = callbacks;
    calls.add('setHandlerCallbacks');
  }

  @override
  Future<void> configure(ConfigureRequest request) async => calls.add(
    'configure(${request.config.androidNotificationChannelId}'
    '|${request.config.androidNotificationChannelName})',
  );

  @override
  Future<void> setState(SetStateRequest request) async =>
      calls.add('setState(${request.state.playing})');

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async =>
      calls.add('setMediaItem(${request.mediaItem.title})');

  @override
  Future<void> setQueue(SetQueueRequest request) async => calls.add('setQueue');

  @override
  Future<void> stopService(StopServiceRequest request) async =>
      calls.add('stopService');

  @override
  Future<void> setAndroidPlaybackInfo(
    SetAndroidPlaybackInfoRequest request,
  ) async => calls.add('setAndroidPlaybackInfo');
}
