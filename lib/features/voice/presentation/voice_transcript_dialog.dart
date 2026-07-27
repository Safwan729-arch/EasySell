import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import 'voice_controller.dart';

/// Opens a small editor prefilled with [current] transcript. On submit,
/// re-runs the AI on the corrected text via the controller. Empty submits are
/// ignored by the controller.
///
/// Shared by two callers: the review sheet (fix a mishear) and the error pane
/// (a noisy room defeated the mic entirely -- type the sale instead of
/// retrying into the same noise). From the error pane [current] is usually
/// empty, since nothing was heard.
Future<void> showVoiceTranscriptDialog(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final controller = TextEditingController(text: current);
  try {
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.voice_heard),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(dialogContext.l10n.voice_recheck),
          ),
        ],
      ),
    );
    if (edited != null) {
      await ref.read(voiceControllerProvider.notifier).reparseFromText(edited);
    }
  } finally {
    // Deferred a frame: the AlertDialog's exit-transition route is still
    // mounted (mid pop-animation) the instant `showDialog` resolves, so
    // disposing synchronously here can race the TextField's own teardown.
    // A post-frame callback runs after that route has actually been
    // removed from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}
