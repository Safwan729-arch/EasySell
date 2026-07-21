import 'voice_parse_result.dart';

/// What the review UI must do with one spoken line.
enum VoiceLineStatus {
  /// One product clearly won -- pre-filled, user can still change it.
  resolved,

  /// The speech did not distinguish between candidates. The user MUST choose.
  ambiguous,

  /// Nothing in the shop's inventory plausibly matches.
  notFound,
}

/// Tunable thresholds mapping model confidences to a review action. Mirrors
/// [ScanThresholds]; calibrate on real speech in Phase 3.
class VoiceThresholds {
  const VoiceThresholds({
    this.strong = 0.80,
    this.margin = 0.15,
    this.ambiguous = 0.50,
    this.maxChoices = 5,
  });

  /// Top-1 must reach this confidence to be pre-filled...
  final double strong;

  /// ...and lead the runner-up by at least this margin. Without this, two
  /// variants of the same product (Pepsi 500ml vs 1L) would be a coin flip
  /// decided by noise.
  final double margin;

  /// Any match at/above this can appear as a choice.
  final double ambiguous;

  /// Cap on candidates offered for one line.
  final int maxChoices;
}

/// The status of one line plus the matches it applies to.
class VoiceLineDecision {
  const VoiceLineDecision(this.status, this.choices);

  final VoiceLineStatus status;

  /// resolved -> exactly one; ambiguous -> the ranked shortlist; notFound -> empty.
  final List<VoiceMatch> choices;
}

/// Pure decision for a single spoken item. No I/O -- fully unit-testable.
VoiceLineDecision decideVoiceLine(
  List<VoiceMatch> matches, {
  VoiceThresholds thresholds = const VoiceThresholds(),
}) {
  final ranked = [...matches]
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  if (ranked.isEmpty) {
    return const VoiceLineDecision(VoiceLineStatus.notFound, []);
  }

  final top = ranked.first;
  final second = ranked.length > 1 ? ranked[1] : null;
  final leadsClearly =
      second == null ||
      (top.confidence - second.confidence) >= thresholds.margin;

  if (top.confidence >= thresholds.strong && leadsClearly) {
    return VoiceLineDecision(VoiceLineStatus.resolved, [top]);
  }

  final plausible = ranked
      .where((m) => m.confidence >= thresholds.ambiguous)
      .toList();
  if (plausible.isNotEmpty) {
    return VoiceLineDecision(
      VoiceLineStatus.ambiguous,
      plausible.take(thresholds.maxChoices).toList(),
    );
  }
  return const VoiceLineDecision(VoiceLineStatus.notFound, []);
}
