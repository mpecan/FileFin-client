import 'package:flutter/material.dart';

/// The app-bar actions both library tabs carry.
///
/// **One list rather than a copy in each page**, because there are now two of
/// them and the pair is what makes the duplication worth naming: `just dupes`
/// fires at 15 lines, and — more to the point — a sign-out that existed on one
/// tab and not the other is exactly the "reachable only from a tab you have to
/// know to visit" problem `HomePage` already argues against for the settings
/// button.
///
/// Each action appears only when it has somewhere to go, so a test that is not
/// about settings or sign-out gets neither.
List<Widget> libraryAppBarActions({
  VoidCallback? onServers,
  VoidCallback? onSettings,
  VoidCallback? onSignOut,
}) => [
  if (onServers != null)
    IconButton(
      onPressed: onServers,
      tooltip: 'Servers',
      icon: const Icon(Icons.dns_outlined),
    ),
  if (onSettings != null)
    IconButton(
      onPressed: onSettings,
      tooltip: 'Playback settings',
      icon: const Icon(Icons.settings_outlined),
    ),
  if (onSignOut != null)
    IconButton(
      onPressed: onSignOut,
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
    ),
];
