import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/cart_line.dart';
import 'cart_controller.dart';

/// Shows a confirmation snackbar with an Undo action that restores the cart to
/// [snapshot]. Shared by the scan and voice add flows so "undo last add"
/// behaves identically in both. Capture [snapshot] BEFORE mutating the cart.
void showUndoableAddSnackBar(
  ScaffoldMessengerState messenger,
  WidgetRef ref, {
  required String message,
  required String undoLabel,
  required List<CartLine> snapshot,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: undoLabel,
          onPressed: () =>
              ref.read(cartControllerProvider.notifier).restore(snapshot),
        ),
      ),
    );
}
