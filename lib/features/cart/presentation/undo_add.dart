import 'package:flutter/material.dart';

/// Shows a confirmation snackbar with an Undo action that calls [onUndo].
/// Shared by the scan and voice add flows so "undo last add" behaves
/// identically in both. Callers must capture whatever [onUndo] needs (e.g. a
/// controller notifier and a pre-add snapshot) BEFORE any navigation that
/// could unmount the calling widget -- the SnackBarAction fires later, once
/// the widget that triggered it may already be gone, so [onUndo] must not
/// depend on a `BuildContext`/`WidgetRef` tied to that widget.
void showUndoableAddSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
}
