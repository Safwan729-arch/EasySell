/// Failure types surfaced by repositories.
///
/// Repositories catch low-level/SDK exceptions (Postgres, Auth, network) and
/// convert them into a [Failure] with a user-friendly [message]. Controllers
/// then surface these as `AsyncError` — never expose raw Postgres/Auth strings
/// to the UI.
sealed class Failure {
  const Failure(this.message, {this.code, this.detail});

  /// Fallback text. English, and only shown when [code] is null or unknown to
  /// the UI — prefer translating [code].
  final String message;

  /// Stable identifier for a condition the UI can translate, e.g.
  /// `insufficientStock`. Null when the failure has no recognised shape.
  ///
  /// This exists because our Postgres functions `raise exception` with English
  /// sentences, and passing those straight to a snackbar leaves a Bengali-first
  /// app showing English at the one moment a sale has just failed (CLAUDE.md §6
  /// forbids surfacing raw Postgres text). Repositories cannot import `l10n` —
  /// that is a presentation concern — so they classify, and the widget layer
  /// translates. See [ServerErrorCodes].
  final String? code;

  /// The one variable part of a coded failure worth showing, e.g. the product
  /// name in "Insufficient stock for Pepsi". Null when there is none.
  final String? detail;

  @override
  String toString() => '$runtimeType($message)';
}

/// Codes set by repositories and translated by the UI. Keep in sync with the
/// `raise exception` texts in `supabase/migrations/` — `transaction_repository`
/// has tests pinning each one against the message the migration actually
/// raises, so changing a migration's wording fails a test rather than silently
/// dropping the app back to English.
abstract final class ServerErrorCodes {
  static const insufficientStock = 'insufficientStock';
  static const cartEmpty = 'cartEmpty';
  static const productNotFound = 'productNotFound';
  static const customerNotFound = 'customerNotFound';
  static const discountExceedsTotal = 'discountExceedsTotal';
  static const discountNegative = 'discountNegative';
  static const quantityNotPositive = 'quantityNotPositive';

  /// Set by the app, not the server: checkout's expiry gate refused a cart
  /// that would sell expired units (expiry spec §5 Cart).
  static const expiredStockInCart = 'expiredStockInCart';

  /// Set by the app: a line's chosen delivery has fewer units than the line.
  static const batchShortInCart = 'batchShortInCart';

  /// Set by the app: a line's product has several batches and the seller has
  /// not picked one.
  static const batchNotChosen = 'batchNotChosen';

  /// `record_sale_cart` refused a delivery (closed, expired, another
  /// product's, or fewer units than the line).
  static const batchNotAvailable = 'batchNotAvailable';
}

/// Matches the product name out of `record_sale_cart`'s stock exception, whose
/// text is `Insufficient stock for %: have %, need %`. Non-greedy up to the
/// `: have `, so a product whose own name contains a colon still resolves.
final _stockRe = RegExp(r'^Insufficient stock for (.+?): have ');

/// Classifies a message raised by one of our Postgres functions into a
/// [ServerErrorCodes] value plus the one variable worth showing.
///
/// Matching is by PREFIX because several of the messages interpolate values.
/// Kept beside the codes, and pure, so it can be tested directly against the
/// exact strings `supabase/migrations/` raises — a migration reworded without
/// updating this drops the app back to English, and a test is the only thing
/// that notices.
({String? code, String? detail}) classifyServerMessage(String message) {
  final stock = _stockRe.firstMatch(message);
  if (stock != null) {
    return (code: ServerErrorCodes.insufficientStock, detail: stock.group(1));
  }
  final code = switch (message) {
    _ when message.startsWith('Cart is empty') => ServerErrorCodes.cartEmpty,
    _ when message.startsWith('Product not found') =>
      ServerErrorCodes.productNotFound,
    _ when message.startsWith('Customer not found') =>
      ServerErrorCodes.customerNotFound,
    _ when message.startsWith('Discount exceeds total') =>
      ServerErrorCodes.discountExceedsTotal,
    _ when message.startsWith('Discount cannot be negative') =>
      ServerErrorCodes.discountNegative,
    _ when message.startsWith('Quantity must be greater than zero') =>
      ServerErrorCodes.quantityNotPositive,
    _ when message.startsWith('Batch not available') =>
      ServerErrorCodes.batchNotAvailable,
    _ => null,
  };
  return (code: code, detail: null);
}

/// Auth-related failure (sign in/up, session, OAuth).
class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code, super.detail});
}

/// Database / RPC failure (Postgres errors, RLS denials, RPC exceptions like
/// "Insufficient stock" raised by `record_sale`).
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.code, super.detail});
}

/// Network connectivity / timeout failure.
class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.code, super.detail});
}

/// Anything not covered above.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.code, super.detail});
}
