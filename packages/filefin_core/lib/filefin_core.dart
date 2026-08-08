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

export 'src/ids.dart';
export 'src/json_converters.dart';
export 'src/models/auth_result.dart';
export 'src/models/category.dart';
export 'src/models/home_rows.dart';
export 'src/models/media_detail.dart';
export 'src/models/media_summary.dart';
export 'src/models/server_state.dart';
