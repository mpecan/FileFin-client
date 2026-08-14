/// The pure-Dart core of the FileFin client.
///
/// Everything reachable from here is I/O-free, Flutter-free and deterministic
///. Time and network state arrive as arguments; nothing in this
/// package reads a clock, a socket or a file.
///
/// This barrel is the package's entire public surface: a symbol not exported
/// here has no consumer outside the library and is dead code. `ApiPaths` is
/// hidden by that same criterion — unhide it the day `filefin_api` needs a
/// bare path.
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
export 'src/playback/progress_policy.dart';
export 'src/playback/resume_choice.dart';
export 'src/resume/detail_state.dart';
export 'src/resume/engine.dart';
export 'src/resume/watch_state.dart';
export 'src/search_field.dart';
export 'src/urls.dart' hide ApiPaths;
