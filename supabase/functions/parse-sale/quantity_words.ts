// Bengali/Banglish fractional quantity words -> numbers.
//
// WHY THIS EXISTS IN CODE RATHER THAN ONLY IN THE PROMPT
//
// Bengali expresses common half-quantities as single, irregular words:
// "আড়াই কেজি" is 2.5 kg, but আড়াই contains no word for "two" -- it is
// suppletive, like English "twelve" rather than "two-teen". A language model
// therefore cannot derive it; it either memorised the token or it guesses. And
// romanized ("Banglish") spellings are exactly where that memorisation is
// weakest: a shopkeeper saying "arai kg loose rice" was reliably parsed as
// quantity 2 -- the half silently dropped -- even at temperature 0.
//
// The mapping is small, closed, and entirely deterministic, so it belongs in
// code, where it is exhaustively testable offline and cannot regress when a
// prompt is edited or a model is upgraded. The prompt still teaches these words
// (a model that gets it right needs no correction); this is the safety net that
// makes the outcome certain instead of likely.
//
// SAFETY PROPERTY: [resolveSpokenQuantity] returns null unless an explicit
// fractional word is present as a whole token. It can therefore only ever
// correct a half-quantity -- it can never invent or alter an ordinary count.

/** A fractional quantity recognised in spoken text. */
export interface SpokenQuantity {
  /** The numeric quantity, e.g. 2.5. */
  value: number;
  /** The token(s) that produced it -- logged so overrides are auditable. */
  matched: string;
}

/// Words that carry a whole fractional value on their own.
const STANDALONE = new Map<string, number>([
  // half
  ["আধা", 0.5], ["আধ", 0.5],
  ["adha", 0.5], ["aadha", 0.5], ["adh", 0.5], ["half", 0.5], ["haf", 0.5],
  // one and a half
  ["দেড়", 1.5],
  ["der", 1.5], ["derh", 1.5], ["dedh", 1.5], ["deed", 1.5], ["deur", 1.5],
  // two and a half
  ["আড়াই", 2.5],
  ["arai", 2.5], ["aarai", 2.5], ["adai", 2.5], ["aadai", 2.5], ["arhai", 2.5],
]);

/// Words that modify the number that FOLLOWS them: "সাড়ে তিন" = 3 + 0.5.
/// Bengali uses these only from three upwards -- 1.5 and 2.5 are দেড়/আড়াই --
/// but no lower bound is enforced, since accepting "সাড়ে দুই" costs nothing.
const PREFIX = new Map<string, number>([
  // + 1/4
  ["সোয়া", 0.25],
  ["shoya", 0.25], ["showa", 0.25], ["soya", 0.25], ["sawa", 0.25],
  // + 1/2
  ["সাড়ে", 0.5],
  ["sare", 0.5], ["share", 0.5], ["saare", 0.5], ["shaare", 0.5],
  ["sadhe", 0.5],
  // - 1/4
  ["পৌনে", -0.25],
  ["poune", -0.25], ["pone", -0.25], ["powne", -0.25], ["pouney", -0.25],
]);

/// Cardinals a [PREFIX] can attach to. Only consulted in the token position
/// immediately after a prefix, which is what keeps everyday English words in
/// this list ("at", "char") from ever being read as numbers on their own.
const CARDINALS = new Map<string, number>([
  ["এক", 1], ["ek", 1],
  ["দুই", 2], ["dui", 2], ["du", 2],
  ["তিন", 3], ["tin", 3],
  ["চার", 4], ["char", 4], ["car", 4],
  ["পাঁচ", 5], ["pach", 5], ["panch", 5], ["paanch", 5],
  ["ছয়", 6], ["choy", 6], ["chhoy", 6],
  ["সাত", 7], ["sat", 7], ["saat", 7],
  ["আট", 8], ["at", 8], ["aat", 8],
  ["নয়", 9], ["noy", 9], ["noi", 9],
  ["দশ", 10], ["dosh", 10], ["dos", 10],
]);

/// Bengali digits ০-৯ share the ASCII digits' meaning but not their code
/// points, so they are folded before any numeric parse.
function foldBengaliDigits(token: string): string {
  return token.replace(
    /[০-৯]/g,
    (d) => String(d.charCodeAt(0) - 0x09e6),
  );
}

/// A cardinal written as a word or as digits (either script), else null.
function cardinal(token: string): number | null {
  const word = CARDINALS.get(token);
  if (word !== undefined) return word;
  const digits = foldBengaliDigits(token);
  if (/^\d+(\.\d+)?$/.test(digits)) return Number(digits);
  return null;
}

/// Splits into whole tokens.
///
/// The character class must include `\p{M}` (combining marks): Bengali vowel
/// signs and the nukta are marks, not letters, so a letters-only split would
/// tear আড়াই into fragments and match nothing. NFC normalisation first, since
/// ড় has both a precomposed form and a ড + nukta form that must compare equal.
function tokenize(text: string): string[] {
  return text
    .normalize("NFC")
    .replace(/[‌‍]/g, "") // zero-width joiners carry no meaning here
    .toLowerCase()
    .split(/[^\p{L}\p{N}\p{M}]+/u)
    .filter((t) => t !== "");
}

/**
 * Finds the fractional quantity spoken in [text], or null when there is none.
 *
 * Scans left to right and returns the first hit, because upstream each item
 * carries its own `heard` fragment -- if two fractional words survive into one
 * string, the leading one is the one attached to this item.
 */
export function resolveSpokenQuantity(text: string): SpokenQuantity | null {
  const tokens = tokenize(text);

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];

    const offset = PREFIX.get(token);
    if (offset !== undefined) {
      // A prefix is only meaningful with a number after it. When there isn't
      // one, fall through and keep scanning rather than guessing a value.
      const next = i + 1 < tokens.length ? cardinal(tokens[i + 1]) : null;
      if (next !== null) {
        return { value: next + offset, matched: `${token} ${tokens[i + 1]}` };
      }
      continue;
    }

    const standalone = STANDALONE.get(token);
    if (standalone !== undefined) {
      return { value: standalone, matched: token };
    }
  }

  return null;
}

/** One item's quantity, before and after fractional-word correction. */
export interface ItemQuantity {
  /**
   * The quantity to send to the app. Null means "none spoken" -- the app
   * defaults that to 1 and flags it as assumed, which stays the right
   * behaviour when no fraction was heard either.
   */
  quantity: number | null;
  /** Non-null only when this function actually changed the model's answer. */
  corrected: SpokenQuantity | null;
}

/**
 * Applies fractional-word correction to one parsed item.
 *
 * Reads the item's own `heard` fragment first. For a **single-item** sentence
 * it also falls back to the whole transcript, because the prompt puts counts in
 * `quantity` rather than `heard`, so the fractional word is frequently absent
 * from the fragment ("loose rice") while sitting plainly in the transcript
 * ("loose rice arai kg").
 *
 * That fallback is deliberately NOT used for multi-item speech: with
 * "আড়াই কেজি চাল আর দুই কেজি চিনি" there is no sound way to decide which item
 * an amount found in the transcript belongs to, and attaching 2.5 kg to the
 * sugar would be worse than leaving the model's answer alone.
 */
export function resolveItemQuantity(opts: {
  heard: string;
  transcript: string;
  modelQuantity: number | null;
  soleItem: boolean;
}): ItemQuantity {
  const spoken = resolveSpokenQuantity(opts.heard) ??
    (opts.soleItem ? resolveSpokenQuantity(opts.transcript) : null);

  if (spoken === null) {
    return { quantity: opts.modelQuantity, corrected: null };
  }
  // Nothing to report when the model already agreed -- keeps the log to real
  // corrections only.
  if (opts.modelQuantity === spoken.value) {
    return { quantity: spoken.value, corrected: null };
  }
  return { quantity: spoken.value, corrected: spoken };
}
