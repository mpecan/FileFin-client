import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

/// One case per sealed variant, and that is the coverage rule doing its job:
/// `describeApiError` is an exhaustive switch, so an untested arm is an
/// uncovered line and `MAX_UNCOVERED=0` says so before a reviewer has to.
///
/// The switch has no default arm on purpose. When M5 adds `TranscodingDisabled`
/// (415, where F12's wording IS the variant), this file stops compiling — which
/// is the alarm. A default arm would render "something went wrong" for the one
/// error the spec asks us to name precisely.
void main() {
  final url = Uri.parse('https://media.example/api/media/abc');

  ErrorMessage describe(FileFinApiException e) => describeApiError(e);

  test('a timeout names the phase, so the next action is obvious', () {
    final connect = describe(RequestTimedOut(RequestPhase.connect, url));
    final receive = describe(RequestTimedOut(RequestPhase.receive, url));

    expect(connect.detail, contains('connecting'));
    expect(receive.detail, contains('reading the response'));
    expect(connect.retryable, isTrue);
    expect(connect.detail, isNot(equals(receive.detail)));
  });

  test('a cancellation is presentable but never shown', () {
    // It is in the switch because exhaustiveness is what makes M5's new
    // variant a compile error. `AsyncController` drops it before a view can
    // ever ask, and `retryable` says so: retrying something the user cancelled
    // is the opposite of what they asked for.
    final message = describe(RequestCancelled(url));

    expect(message.retryable, isFalse);
    expect(message.needsSignIn, isFalse);
  });

  test('an unreachable server is retryable and shows the OS words', () {
    final message = describe(
      ConnectionFailed(url, cause: 'Connection refused'),
    );

    expect(message.retryable, isTrue);
    expect(message.detail, contains('Connection refused'));
  });

  test('a connection failure with no cause still says something', () {
    // `cause` is nullable, and a detail that renders "null" is worse than a
    // shorter sentence.
    final message = describe(ConnectionFailed(url));

    expect(message.detail, isNotEmpty);
    expect(message.detail, isNot(contains('null')));
  });

  test('SessionExpired routes to sign-in rather than offering a retry', () {
    // F3 already re-authenticated and retried once. Reaching here means that
    // failed, so a retry button would repeat exactly what did not work.
    final message = describe(SessionExpired(url));

    expect(message.needsSignIn, isTrue);
    expect(message.retryable, isFalse);
    expect(message.title.toLowerCase(), contains('sign in'));
  });

  test('a 404 is about the item, not about the server', () {
    final message = describe(NotFound(url));

    expect(message.retryable, isFalse);
    expect(message.title.toLowerCase(), contains('not'));
  });

  test('CacheUnavailable suggests rather than promises a rebuild', () {
    // media.go:192-198 writes `cache unavailable` for ANY ensureDB failure,
    // and a rebuild is only one of them — a message promising one would tell a
    // user to wait for something that may never finish.
    final message = describe(CacheUnavailable(url));

    expect(message.retryable, isTrue);
    expect(message.detail.toLowerCase(), contains('possibly'));
  });

  test('RateLimited names the seconds it was told to wait', () {
    final message = describe(
      RateLimited(const Duration(seconds: 42), url, rawRetryAfter: '42'),
    );

    // Verbatim, not `contains`. M1 learned this on `RangeError`'s bounds: a
    // message is mutable source and nothing else in the suite reads it, so
    // `just mutants` rewrites the prose — the hyphen in "sign-in" became a
    // plus — and every loose assertion still passed. What a user reads is
    // worth pinning exactly.
    expect(
      message.detail,
      'The server is refusing sign-in attempts for another 42 seconds.',
    );
    expect(message.retryable, isFalse);
  });

  test('RateLimited with an unparsed header does not invent a number', () {
    // Duration.zero means "we do not know", not "retry immediately"
    // (filefin_api's errors.dart). Rendering "wait 0 seconds" would be a guess
    // presented as a fact.
    final message = describe(
      RateLimited(Duration.zero, url, rawRetryAfter: 'tomorrow'),
    );

    expect(
      message.detail,
      'The server is refusing sign-in attempts for a while. Five wrong '
      'passwords lock an account for fifteen minutes.',
    );
    expect(message.detail, isNot(contains('0 second')));
  });

  test('MalformedIdentifier blames the server, not the user', () {
    // The value came off the wire: MediaSummary.id defaults to MediaId('')
    // under §8's tolerant decoding, so a payload with a missing id produces
    // one. Telling a user they mistyped something they never typed is worse
    // than saying nothing.
    final message = describe(const MalformedIdentifier('', 'media id'));

    expect(message.detail.toLowerCase(), contains('server'));
    expect(message.detail, contains('media id'));
    expect(message.retryable, isFalse);
  });

  test('InvalidCredentials does not claim to know which of the three', () {
    // auth.go:157-169 runs exactly one bcrypt compare against a dummy hash
    // when the account does not exist, so neither the body nor the timing
    // separates wrong-password from unknown-account. A client that guessed
    // would be inventing information.
    final message = describe(InvalidCredentials(url));
    final text = '${message.title} ${message.detail}'.toLowerCase();

    expect(text, isNot(contains('no such user')));
    expect(text, isNot(contains('unknown account')));
    expect(message.retryable, isFalse);
  });

  test('NotAFileFinServerResponse says it answered but is not FileFin', () {
    final message = describe(
      NotAFileFinServerResponse(url, 'text/html; charset=utf-8'),
    );

    expect(message.detail.toLowerCase(), contains('not a filefin server'));
    expect(message.retryable, isFalse);
  });

  test('MalformedResponse is the opposite of NotAFileFinServerResponse', () {
    // That one says "this is not the server you think it is"; this one says
    // "this IS the server and it sent something we cannot read". Collapsing
    // them would send a user to check an address that is perfectly correct.
    final message = describe(MalformedResponse(url, 'expected an object'));

    expect(message.detail.toLowerCase(), isNot(contains('not a filefin')));
    expect(message.detail, contains('expected an object'));
  });

  test('ServerFailure carries the status, because a bug report needs it', () {
    final message = describe(ServerFailure(500, 'internal error', url));

    expect(message.detail, contains('500'));
    expect(message.retryable, isTrue);
  });

  test('CertificateNotTrusted is a decision, not a retry', () {
    // F15: the fingerprint has to be shown and accepted. A retry button would
    // invite mashing it until something gives.
    final message = describe(
      CertificateNotTrusted(
        url,
        fingerprint: 'AA:BB',
        subject: '/CN=nas.local',
        issuer: '/CN=nas.local',
        validTo: DateTime.utc(2027),
      ),
    );

    expect(
      message.detail,
      'It identifies itself as /CN=nas.local with fingerprint AA:BB, valid '
      'until 2027-01-01. Self-hosted servers commonly use a certificate '
      'nobody else vouches for; check the fingerprint before accepting it.',
    );
    expect(message.retryable, isFalse);
  });

  test('CertificatePinMismatch is loud and shows both fingerprints', () {
    // F15 again: a changed fingerprint is a blocking warning, not a silent
    // re-accept, and a user cannot judge it without seeing both values.
    final message = describe(
      CertificatePinMismatch(url, expected: 'AA:BB', actual: 'CC:DD'),
    );

    expect(message.detail, contains('AA:BB'));
    expect(message.detail, contains('CC:DD'));
    expect(message.retryable, isFalse);
  });

  group('the whole sealed hierarchy, one row per variant', () {
    // ONE table for the three sweeps that used to keep their own lists. The
    // redaction sweep kept 11 of the 14 variants by hand and quietly omitted
    // MalformedIdentifier, CertificateNotTrusted and CertificatePinMismatch —
    // a hand-maintained "every variant" list is a list of the variants
    // somebody remembered.
    //
    // Every URL here carries `sam:hunter2@`, so the redaction sweep runs over
    // all of them rather than over a second, shorter list.
    final secret = Uri.parse('https://sam:hunter2@nas.local/api/me');
    final all = <FileFinApiException>[
      RequestTimedOut(RequestPhase.send, secret),
      RequestCancelled(secret),
      ConnectionFailed(secret, cause: 'Connection refused'),
      SessionExpired(secret),
      NotFound(secret),
      CacheUnavailable(secret),
      RateLimited(const Duration(seconds: 1), secret),
      const MalformedIdentifier('', 'media id'),
      InvalidCredentials(secret),
      NotAFileFinServerResponse(secret, 'text/html'),
      MalformedResponse(secret, 'expected an object'),
      ServerFailure(500, 'internal error', secret),
      // The 15th row, and the reason this group exists. See below.
      ServerFailure(401, 'unauthorized', secret),
      CertificateNotTrusted(
        secret,
        fingerprint: 'AA',
        subject: 's',
        issuer: 'i',
        validTo: DateTime.utc(2027),
      ),
      CertificatePinMismatch(secret, expected: 'AA', actual: 'BB'),
    ];

    test('the table really does cover every variant', () {
      // `expectedNeedsSignIn` below is an exhaustive switch with no default,
      // so a variant added to `filefin_api` stops this file compiling — the
      // same alarm `describeApiError` itself carries. This length check is the
      // other half: it catches a variant added to the switch and forgotten
      // here.
      expect(all, hasLength(15));
      expect(all.map((e) => e.runtimeType).toSet(), hasLength(14));
    });

    test('only SessionExpired asks for a password — a 401 never does', () {
      // **THE 401 DISCIPLINE, asserted at last.** The sibling test in
      // `sign_in_page_test.dart` drives a fake that SUCCEEDS: no 401, no
      // retry, no interceptor, and nothing about it can fail when the rule is
      // broken. Adding `needsSignIn: statusCode == 401` to the `ServerFailure`
      // arm — precisely the UI-level 401 handler the rule forbids — left all
      // 181 tests green. It does not any more; the row is in the table above.
      //
      // Server sessions live in memory and die with the process (SPEC.md L1),
      // so a 401 on any call is routine. `filefin_api` re-authenticates and
      // replays once (F3) and the caller never sees it. A UI that prompted on
      // a raw 401 would ask for a password every time a server restarted
      // mid-scroll, which is the experience F2 and F3 exist to prevent.
      for (final error in all) {
        expect(
          describe(error).needsSignIn,
          expectedNeedsSignIn(error),
          reason: '$error',
        );
      }
    });

    test('no message leaks a password out of a URL (§9, NF4)', () {
      // A message is a log line waiting to happen, and a saved-server URL is
      // typed by a user — `https://sam:hunter2@nas.local/` is a thing people
      // type. Every variant that echoes a URL must go through redactUserInfo.
      for (final error in all) {
        final message = describe(error);
        expect(
          '${message.title} ${message.detail}',
          isNot(contains('hunter2')),
          reason: '${error.runtimeType} leaked a password',
        );
      }
    });

    test('every message has a title and a detail worth reading', () {
      // "Something went wrong." is the failure mode this whole file exists
      // against; an empty or one-word detail is the same thing with fewer
      // letters.
      for (final error in all) {
        final message = describe(error);
        expect(
          message.title.length,
          greaterThan(3),
          reason: '${error.runtimeType}',
        );
        expect(
          message.detail.length,
          greaterThan(15),
          reason: '${error.runtimeType}',
        );
      }
    });
  });
}

/// Whether a variant is allowed to send the user to the sign-in screen.
///
/// **Exhaustive, with no default arm**, for the same reason `describeApiError`
/// is: a variant added to `filefin_api` stops this file compiling rather than
/// silently inheriting somebody's default. Written as one arm per variant
/// instead of `e is SessionExpired` so that adding, say, a future
/// `PasswordChanged` forces an answer rather than getting `false` for free.
bool expectedNeedsSignIn(FileFinApiException error) => switch (error) {
  SessionExpired() => true,
  RequestTimedOut() ||
  RequestCancelled() ||
  ConnectionFailed() ||
  NotFound() ||
  CacheUnavailable() ||
  RateLimited() ||
  MalformedIdentifier() ||
  InvalidCredentials() ||
  NotAFileFinServerResponse() ||
  MalformedResponse() ||
  ServerFailure() ||
  CertificateNotTrusted() ||
  CertificatePinMismatch() => false,
};
