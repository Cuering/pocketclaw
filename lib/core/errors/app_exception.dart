// lib/core/errors/app_exception.dart
//
// Typed exception hierarchy for PocketClaw. Anything we `throw` on purpose
// should extend one of these — never a raw String, never a bare Exception.
// Reason: in `catch` blocks we want to match on TYPE, not parse strings.

// Base class for all PocketClaw-thrown exceptions.
//
// `implements Exception`: declares this class satisfies Dart's `Exception`
// interface, so it can be thrown and caught like any standard exception.
// We use `implements` instead of `extends` because `Exception` is an interface
// in Dart, not a class with logic to inherit.
class AppException implements Exception {
  // The human-readable message. `final` = set once in constructor, never changed.
  final String message;

  // Optional underlying cause (e.g. the original SocketException that triggered
  // our higher-level error). `Object?` because Dart errors can be ANY object,
  // and `?` makes it nullable.
  final Object? cause;

  // The constructor. `const` allows callers to write `const AppException(...)`
  // for compile-time-constant exceptions (cheap to allocate, reusable).
  //
  // `this.message` is shorthand for "assign the parameter to the field of the
  // same name." `[this.cause]` is a positional optional parameter.
  const AppException(this.message, [this.cause]);

  // `@override` tells the compiler "I'm intentionally replacing the parent's
  // method." If we mistype the name, the compiler catches it.
  //
  // We override `toString()` so error logs are readable instead of showing
  // "Instance of 'AppException'".
  @override
  String toString() {
    if (cause != null) {
      return '$runtimeType: $message (cause: $cause)';
    }
    return '$runtimeType: $message';
  }
}

// Specific subclass for anything Gemma-related: model install, load, inference.
// `extends AppException` means: a GemmaException IS an AppException — so a
// `catch (e) if (e is AppException)` will catch this too.
class GemmaException extends AppException {
  const GemmaException(super.message, [super.cause]);
}

// We'll add more subclasses later as we need them:
//   PermissionException, ScreenCaptureException, StorageException, etc.
// One per concern. Don't pre-create them; add when actually thrown.
