import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';

/// F4's poster grid: one category's direct children, drawn by [MediaGrid].
///
/// The virtualisation and its reasoning moved to [MediaGrid] at M6.5, because
/// search draws the same shape. What is left here is what is genuinely about a
/// *category*: which listing to fetch, the leaf in the app bar, and the empty
/// state — which is a different sentence from search's and so cannot be shared.
class CategoryGridPage extends StatefulWidget {
  /// Browses [category] through [api]; [onOpen] opens an item.
  const CategoryGridPage({
    required this.api,
    required this.category,
    required this.onOpen,
    this.onSignIn,
    super.key,
  });

  /// The port the listing and the posters come from.
  final LibraryApi api;

  /// Which category is being browsed.
  final Category category;

  /// Opens one item's detail view.
  final void Function(MediaSummary item) onOpen;

  /// Where a `SessionExpired` sends the user.
  final VoidCallback? onSignIn;

  @override
  State<CategoryGridPage> createState() => _CategoryGridPageState();
}

class _CategoryGridPageState extends State<CategoryGridPage> {
  late final AsyncController<List<MediaSummary>> _controller =
      AsyncController<List<MediaSummary>>(
        (token) =>
            widget.api.categoryMedia(widget.category.id, cancelToken: token),
      );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.category.leaf)),
    body: AsyncView<List<MediaSummary>>(
      controller: _controller,
      onSignIn: widget.onSignIn,
      builder: (context, items) => items.isEmpty
          ? const _EmptyCategory()
          : MediaGrid(api: widget.api, items: items, onOpen: widget.onOpen),
    ),
  );
}

/// A category the server listed with nothing in it.
class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Nothing in this category. If you expected something here, the '
        "server's library may still be scanning.",
        textAlign: TextAlign.center,
      ),
    ),
  );
}
