import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/browse/search_controller.dart';
import 'package:filefin_mobile/src/browse/search_field_labels.dart';
import 'package:filefin_mobile/src/browse/search_query.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';

/// F5: a box, a scope, and the same poster grid the library uses.
///
/// **The scope selector is not decoration**: an unrecognised `field` degrades
/// to `all` rather than erroring (`docs/field-notes.md`), so a screen that
/// dropped it still returns plausible results while ignoring what the user
/// picked. The test that matters asserts the wire, not the rendering.
///
/// **The box, the scope and the results survive a tab round trip**, because
/// `LibraryShell` keeps a selected tab `Offstage`. Nothing survives a sign-out
/// or a relaunch, because the whole shell goes with it.
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
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        // 48 for `androidTapTargetGuideline`, as elsewhere.
                        height: 48,
                        child: TextField(
                          autofocus: true,
                          style: TextStyle(fontSize: 14, color: palette.text),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: palette.bar,
                            hintText: 'Search',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: palette.textDim,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 17,
                              color: palette.textDim,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 36,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            border: _border(palette.outline),
                            enabledBorder: _border(palette.outline),
                            focusedBorder: _border(palette.accent),
                          ),
                          onChanged: _controller.setText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ScopeButton(
                      field: _controller.query.field,
                      palette: palette,
                      onChanged: _controller.setField,
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
                        child: Text(
                          notice,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.textMuted),
                        ),
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
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color),
  );
}

/// The eleven scopes, behind one pill.
///
/// **A menu rather than the row of pills the TV screen draws**, because there
/// are eleven of them: `db/search.go:70` degrades an unrecognised `field` to
/// `all` without erroring, so every scope the client can send has to be
/// nameable, and eleven pills do not fit across a phone at a legible size.
class _ScopeButton extends StatelessWidget {
  const _ScopeButton({
    required this.field,
    required this.palette,
    required this.onChanged,
  });

  final SearchField field;
  final FileFinPalette palette;
  final ValueChanged<SearchField> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<SearchField>(
    tooltip: 'Search scope',
    initialValue: field,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final value in SearchField.values)
        PopupMenuItem(value: value, child: Text(searchFieldLabel(value))),
    ],
    child: Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.accentFill,
        border: Border.all(color: palette.accent),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            searchFieldLabel(field),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.accentSoft,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 15,
            color: palette.accentSoft,
          ),
        ],
      ),
    ),
  );
}
