import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/browse/search_controller.dart';
import 'package:filefin_mobile/src/browse/search_field_labels.dart';
import 'package:filefin_mobile/src/browse/search_query.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:filefin_mobile/src/tv/tv_keyboard.dart';
import 'package:filefin_mobile/src/tv/tv_row.dart';
import 'package:flutter/material.dart';

/// On a television: an on-screen keyboard, and the results beside it.
///
/// **The keyboard is on screen because there is no other one.** Android TV's
/// system IME covers the results while it is up, so the design draws the keys
/// itself and keeps the grid visible while a query is typed — which is what
/// makes a three-letter query enough to stop typing.
class TvSearchPage extends StatefulWidget {
  /// Searches through [api]; [onOpen] opens a result.
  const TvSearchPage({
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

  /// Where a `SessionExpired` sends the user.
  final VoidCallback? onSignIn;

  /// How long typing is coalesced for. Injected so a test need not wait.
  final Duration debounce;

  @override
  State<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends State<TvSearchPage> {
  late final MediaSearchController _controller = MediaSearchController(
    api: widget.api,
    debounce: widget.debounce,
  );

  var _text = '';

  @override
  void initState() {
    super.initState();
    // Publishes the blank outcome so the screen opens on a sentence rather
    // than on a spinner. It issues no request — the controller refuses first.
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _type(String key) => _setText('$_text$key');

  void _backspace() {
    if (_text.isEmpty) return;
    _setText(_text.substring(0, _text.length - 1));
  }

  void _setText(String text) {
    setState(() => _text = text);
    _controller.setText(text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 436,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: palette.hairline)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Field(text: _text, palette: palette),
                    const SizedBox(height: 20),
                    Expanded(
                      child: TvKeyboard(
                        onKey: _type,
                        onSpace: () => _type(' '),
                        onBackspace: _backspace,
                      ),
                    ),
                    Text(
                      'OK types · ▶ from the last column enters results',
                      style: mono(size: 13, color: palette.textFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 34, 44, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Scopes(
                    chosen: _controller.query.field,
                    palette: palette,
                    onChoose: _controller.setField,
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: AsyncView<SearchOutcome>(
                      controller: _controller.results,
                      onSignIn: widget.onSignIn,
                      builder: (context, outcome) {
                        final notice = searchNotice(outcome);
                        if (notice != null) {
                          return Center(
                            child: Text(
                              notice,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                color: palette.textMuted,
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
          ),
        ],
      ),
    );
  }
}

/// What has been typed so far, with the design's caret.
class _Field extends StatelessWidget {
  const _Field({required this.text, required this.palette});

  final String text;
  final FileFinPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF12141F),
      border: Border.all(color: palette.outlineStrong),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(Icons.search, size: 20, color: palette.textDim),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 20, color: palette.text),
          ),
        ),
        Container(width: 2, height: 24, color: palette.accent),
      ],
    ),
  );
}

/// The eleven scopes, as the design's pills.
///
/// All eleven, scrolled, rather than the three the design draws: `db/search.go`
/// degrades an unrecognised `field` to `all` without erroring, so a scope the
/// client can send and cannot name would return plausible results under the
/// wrong label.
class _Scopes extends StatelessWidget {
  const _Scopes({
    required this.chosen,
    required this.palette,
    required this.onChoose,
  });

  final SearchField chosen;
  final FileFinPalette palette;
  final ValueChanged<SearchField> onChoose;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: SearchField.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final field = SearchField.values[index];
        final selected = field == chosen;
        return TvFocusable(
          onSelect: () => onChoose(field),
          child: InkWell(
            onTap: () => onChoose(field),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.accentFill : null,
                border: Border.all(
                  color: selected ? palette.accent : palette.outline,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                searchFieldLabel(field),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? palette.accentSoft : palette.textMuted,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
