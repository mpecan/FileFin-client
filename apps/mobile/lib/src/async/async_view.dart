import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/ui_state.dart';
import 'package:filefin_mobile/src/errors/error_panel.dart';
import 'package:flutter/material.dart';

/// Draws one [AsyncController]'s three states, for every screen in the app.
///
/// **One widget, three screens, and that is the structural point.** Three
/// screens each writing their own loading / error / data branch is ~20 lines
/// repeated three times, which trips `just dupes` at 15 lines and 50 tokens —
/// and long before the gate notices, it is three places for the error
/// rendering to drift apart.
///
/// The switch has no default arm, so a fourth `UiState` would be a compile
/// error rather than a blank screen.
class AsyncView<T> extends StatelessWidget {
  /// Watches [controller] and hands its data to [builder].
  const AsyncView({
    required this.controller,
    required this.builder,
    this.onSignIn,
    super.key,
  });

  /// The controller whose state is drawn.
  final AsyncController<T> controller;

  /// Draws the loaded value.
  final Widget Function(BuildContext context, T value) builder;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => switch (controller.state) {
      UiLoading<T>() => const Center(child: CircularProgressIndicator()),
      UiData<T>(:final value) => builder(context, value),
      UiFailure<T>(:final error) => ErrorPanel(
        error: error,
        onRetry: controller.load,
        onSignIn: onSignIn,
      ),
    },
  );
}
