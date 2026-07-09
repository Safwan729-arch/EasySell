enum VoiceIntentType { sell, total, cancel, unknown }

class VoiceIntentMatcher {
  /// The default dictionary mapping spoken phrases to system actions.
  /// We include common variations used by local shopkeepers!
  static const Map<VoiceIntentType, List<String>> _dictionary = {
    VoiceIntentType.sell: [
      'sell', 'add', 
      'bechbo', 'bechechi', 'bechtesi', // 🇧🇩 Bangla variations for selling
      'bikri', 'bikri korlam'
    ],
    VoiceIntentType.total: [
      'total', 'checkout', 'hishab', 'koto holo', 'bill'
    ],
    VoiceIntentType.cancel: [
      'cancel', 'delete', 'baad', 'bhul hoyeche'
    ],
  };

  /// Takes the raw text from the speech recognizer and identifies the action.
  static VoiceIntentType parseTranscript(String rawText) {
    final cleanedText = rawText.toLowerCase().trim();

    for (final entry in _dictionary.entries) {
      final intent = entry.key;
      final keywords = entry.value;

      // Look for any exact keyword matches inside the spoken transcript string
      for (final keyword in keywords) {
        if (cleanedText.contains(keyword)) {
          return intent;
        }
      }
    }

    return VoiceIntentType.unknown;
  }
}