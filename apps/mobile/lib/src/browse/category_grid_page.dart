import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// F4's poster grid, and NF2's subject.
///
/// **The whole array arrives at once** — nothing on this server paginates
/// (SPEC.md L2) — so the grid must be virtualised and the posters lazy. What
/// that means concretely, and what the tests assert:
///
/// - `GridView.builder` with an `itemCount`, so per-frame build and layout cost
///   O(visible) rather than O(everything). A `Column` or a `.map().toList()`
///   over the items would quietly make it O(everything) again.
/// - `addAutomaticKeepAlives: false`, so a tile scrolled away is really
///   disposed — which is what cancels its poster request. With keep-alives on,
///   every tile ever visited stays live and holds its bytes. **Stated as a
///   guard rather than as a tested invariant:** a keep-alive only exists once
///   a child mixes in `AutomaticKeepAliveClientMixin`, nothing under
///   `apps/mobile/lib` does, so flipping this flag today changes nothing and
///   no test can see it. It is here for the tile that one day does.
/// - the item list is whatever the controller loaded. `build()` does no
///   sorting, filtering or copying, because all three are O(n) per frame.
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
      builder: (context, items) {
        if (items.isEmpty) return const _EmptyCategory();
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          // A max EXTENT rather than a fixed cross-axis count: the tile stays
          // a readable size on a phone and on a tablet, instead of three
          // enormous tiles across on the second one.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            childAspectRatio: 2 / 3.6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          // Explicit, so the invariant the tests assert is a property of this
          // file rather than of whatever the framework defaults to today.
          scrollCacheExtent: const ScrollCacheExtent.pixels(400),
          addAutomaticKeepAlives: false,
          itemCount: items.length,
          itemBuilder: (context, index) => PosterTile(
            api: widget.api,
            item: items[index],
            onOpen: widget.onOpen,
          ),
        );
      },
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
