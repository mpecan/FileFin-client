import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/browse/search_controller.dart';
import 'package:filefin_mobile/src/browse/search_field_labels.dart';
import 'package:filefin_mobile/src/browse/search_query.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';

/// F5: a box, a scope, and the same poster grid the library uses.
///
/// **The scope selector is not decoration.** `db/search.go:70` degrades an
/// unrecognised `field` to `all` rather than erroring, so a screen that dropped
/// the selector still returns plausible results and quietly ignores what the
/// user picked. The widget test that matters here asserts the wire —
/// `search(Kurosawa, director)`, never `search(Kurosawa, all)`.
///
/// **The box, the scope and the results DO survive a tab round trip**, and this
/// paragraph used to say the opposite. The claim was that the shell rebuilds
/// this tab on every visit; it does not — `LibraryShell` keeps a selected tab
/// `Offstage`, which is what its own doc comment says and what
/// `library_shell_test.dart` now pins. Nothing survives a sign-out or a
/// relaunch, because the whole shell goes with it.
///
/// It is the better behaviour of the two: switching to Home to check something
/// and coming back is the common move, and re-typing the query afterwards is a
/// cost with no benefit. Said here because two files disagreeing about state
/// that lives in one of them is how a "fix" gets made to the wrong one.
class SearchPage extends StatefulWidget {
  /// Searches through [api]; [onOpen] opens a result.
  const SearchPage({
    required this.api,
    required this.onOpen,
    this.onSignIn,
    this.debounce = const Duration(milliseconds: 300),
    super.key,
  });

  /// Where the results and the posters come from.
  final LibraryApi api;

  /// Opens one result's detail view.
  final void Function(MediaSummary item) onOpen;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  /// How long typing is coalesced for. Injected so a test need not wait.
  final Duration debounce;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final MediaSearchController _controller = MediaSearchController(
    api: widget.api,
    debounce: widget.debounce,
  );

  @override
  void initState() {
    super.initState();
    // Publishes the blank outcome so the screen opens on a sentence rather
    // than on a spinner. It issues no request — `_fetch` refuses first.
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _controller.setText,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<SearchField>(
                  value: _controller.query.field,
                  onChanged: (field) {
                    if (field != null) _controller.setField(field);
                  },
                  items: [
                    for (final field in SearchField.values)
                      DropdownMenuItem(
                        value: field,
                        child: Text(searchFieldLabel(field)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: AsyncView<SearchOutcome>(
            controller: _controller.results,
            onSignIn: widget.onSignIn,
            builder: (context, outcome) {
              final notice = searchNotice(outcome);
              if (notice != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(notice, textAlign: TextAlign.center),
                  ),
                );
              }
              return MediaGrid(
                api: widget.api,
                items: outcome.results,
                onOpen: widget.onOpen,
              );
            },
          ),
        ),
      ],
    ),
  );
}
