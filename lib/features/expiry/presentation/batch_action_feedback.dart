import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../l10n/app_localizations.dart';
import 'batch_actions_controller.dart';

/// Tells the shopkeeper why a delivery action (remove, none left, not
/// expired) failed. Those buttons live on the product page and in the cart,
/// neither of which otherwise listens to [batchActionsControllerProvider] --
/// without this a failed tap simply did nothing.
void showBatchActionFailure(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
) {
  final error = ref.read(batchActionsControllerProvider).error;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          error is Failure
              ? failureText(l10n, error)
              : l10n.common_somethingWrong,
        ),
      ),
    );
}
