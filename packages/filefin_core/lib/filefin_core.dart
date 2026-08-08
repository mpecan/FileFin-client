/// The pure-Dart core of the FileFin client.
///
/// Everything reachable from here is I/O-free, Flutter-free and deterministic
/// (CLAUDE.md §6). Time and network state arrive as arguments; nothing in this
/// package reads a clock, a socket or a file.
///
/// This barrel is the package's entire public surface: `lib/src/**` is private
/// by convention, so a symbol that is not exported here has no consumer outside
/// the library and is dead by §5.
library;

export 'src/category_tree.dart';
export 'src/ids.dart';
export 'src/json_converters.dart';
export 'src/models/auth_result.dart';
export 'src/models/category.dart';
export 'src/models/home_rows.dart';
export 'src/models/media_detail.dart';
export 'src/models/media_summary.dart';
export 'src/models/server_state.dart';
export 'src/playback/decision.dart';
export 'src/resume/engine.dart';
export 'src/resume/watch_state.dart';
export 'src/search_field.dart';
// `ApiPaths` is hidden rather than exported: nothing outside this library uses
// it, and by the criterion above that makes exporting it a §5 claim we cannot
// back. It is `FileFinUrls`'s own route table, and `undocumented_endpoint`
// (§8) reads its literals straight out of the source, not through the barrel.
// `urls_test.dart` imports `src/urls.dart` directly to pin them. Unhide it the
// day `filefin_api` genuinely needs a bare path.
export 'src/urls.dart' hide ApiPaths;
