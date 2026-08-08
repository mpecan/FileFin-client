import 'package:filefin_api/filefin_api.dart';
import 'package:meta/meta.dart';

/// What one screen's one asynchronous fetch currently is.
///
/// Three states and no fourth. Deliberately not "loading + data + error + a
/// nullable of each": a screen that can hold data *and* an error at once has
/// four renderings to design and two of them never happen. Sealed, so
/// `AsyncView` switches over it with no default arm and a new state would be a
/// compile error rather than a blank screen.
///
/// There is no `UiEmpty`. An empty list is data — it is `UiData(const [])` —
/// and giving it its own state is how "no results" and "not loaded yet" end up
/// looking the same to the code that decides which one to draw.
@immutable
sealed class UiState<T> {
  /// Allows the variants below to be `const`.
  const UiState();
}

/// Nothing has arrived yet. Also the state a retry returns to.
final class UiLoading<T> extends UiState<T> {
  /// The initial state of every controller.
  const UiLoading();
}

/// The fetch succeeded and produced [value].
final class UiData<T> extends UiState<T> {
  /// Holds [value], exactly as the port returned it.
  const UiData(this.value);

  /// What arrived.
  final T value;
}

/// The fetch failed with [error].
///
/// It carries the exception itself rather than a rendered string, because the
/// decision of what to *say* belongs to `describeApiError` — one exhaustive
/// switch in one place — and a controller that formatted messages would put
/// prose in a layer with no idea what screen it is on.
final class UiFailure<T> extends UiState<T> {
  /// Holds the failure, unwrapped and untranslated.
  const UiFailure(this.error);

  /// What went wrong, in `filefin_api`'s vocabulary.
  final FileFinApiException error;
}
