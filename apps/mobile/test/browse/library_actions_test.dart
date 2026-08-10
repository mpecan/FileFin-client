import 'package:filefin_mobile/src/browse/library_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app-bar actions both library tabs carry, and the three guards on them.
///
/// **Two of the three were deletable and green.** `library_actions.dart:19` and
/// `:31` — the `if (onServers != null)` and `if (onSignOut != null)` arms —
/// could each be removed without a single assertion objecting, because every
/// suite that renders a tab passes all three callbacks and every suite that
/// passes none asserts on something else. A guard nothing exercises in both
/// directions is a guard that will be deleted by accident.
///
/// It is a pure function, so this needs no widget tree at all.
void main() {
  test('nothing to go to, nothing on the bar', () {
    // The default a test that is about neither settings nor sign-out gets, and
    // the arm that makes the three guards mean anything.
    expect(libraryAppBarActions(), isEmpty);
  });

  test('each callback puts its own action there, and only its own', () {
    IconData iconOf(Widget w) => ((w as IconButton).icon as Icon).icon!;

    expect(
      libraryAppBarActions(onServers: () {}).map(iconOf),
      [Icons.dns_outlined],
    );
    expect(
      libraryAppBarActions(onSettings: () {}).map(iconOf),
      [Icons.settings_outlined],
    );
    expect(
      libraryAppBarActions(onSignOut: () {}).map(iconOf),
      [Icons.logout],
    );
  });

  test('all three, in the order a tab draws them', () {
    // The order is not decoration: sign-out is the destructive one and sits
    // furthest from where a thumb rests, which is only true while it is last.
    expect(
      libraryAppBarActions(
        onServers: () {},
        onSettings: () {},
        onSignOut: () {},
      ).map((w) => (w as IconButton).tooltip),
      ['Servers', 'Playback settings', 'Sign out'],
    );
  });
}
