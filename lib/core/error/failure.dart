/// Failure types surfaced by repositories.
///
/// Repositories catch low-level/SDK exceptions (Postgres, Auth, network) and
/// convert them into a [Failure] with a user-friendly [message]. Controllers
/// then surface these as `AsyncError` — never expose raw Postgres/Auth strings
/// to the UI.
sealed class Failure {
  const Failure(this.message);

  /// User-facing, safe-to-display message.
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// Auth-related failure (sign in/up, session, OAuth).
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Database / RPC failure (Postgres errors, RLS denials, RPC exceptions like
/// "Insufficient stock" raised by `record_sale`).
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

/// Network connectivity / timeout failure.
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// Anything not covered above.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}
