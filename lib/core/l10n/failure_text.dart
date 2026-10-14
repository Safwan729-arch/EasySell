import '../../l10n/app_localizations.dart';
import '../error/failure.dart';

/// Renders a [Failure] in the user's language.
///
/// Repositories classify a server exception into a [Failure.code]; this is
/// where that code becomes text. The split exists because the data layer must
/// not import `l10n` — and because our Postgres functions raise English
/// sentences, which a Bengali-first app cannot show verbatim (CLAUDE.md §6).
///
/// Falls back to [Failure.message] when the code is null or unrecognised, so an
/// unclassified error still says something specific rather than a shrug. That
/// fallback is English; it is the honest last resort, not the normal path.
String failureText(AppLocalizations l10n, Failure failure) =>
    switch (failure.code) {
      ServerErrorCodes.insufficientStock => l10n.error_insufficientStock(
        failure.detail ?? '',
      ),
      ServerErrorCodes.cartEmpty => l10n.error_cartEmpty,
      ServerErrorCodes.productNotFound => l10n.error_productNotFound,
      ServerErrorCodes.customerNotFound => l10n.error_customerNotFound,
      ServerErrorCodes.discountExceedsTotal => l10n.error_discountExceedsTotal,
      ServerErrorCodes.discountNegative => l10n.error_discountNegative,
      ServerErrorCodes.quantityNotPositive => l10n.error_quantityNotPositive,
      ServerErrorCodes.expiredStockInCart => l10n.error_expiredStockInCart,
      _ => failure.message,
    };
