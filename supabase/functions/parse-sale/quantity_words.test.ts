// Run with:  node --test supabase/functions/parse-sale/quantity_words.test.ts
//
// Node (not Deno) so this is runnable in the app repo's own toolchain; the
// module under test is plain TypeScript with no runtime-specific APIs, so the
// same file is what ships to the Edge Function.
import test from "node:test";
import assert from "node:assert/strict";

import { resolveItemQuantity, resolveSpokenQuantity } from "./quantity_words.ts";

/** Asserts the resolved numeric value, ignoring which token matched. */
function value(text: string): number | null {
  return resolveSpokenQuantity(text)?.value ?? null;
}

test("standalone suppletive fractions in Bengali script", () => {
  assert.equal(value("আড়াই কেজি খোলা চাল"), 2.5);
  assert.equal(value("দেড় কেজি চিনি"), 1.5);
  assert.equal(value("আধা কেজি ডাল"), 0.5);
});

test("the same fractions written in romanized Banglish", () => {
  // This is the exact transcript shape that shipped the bug: the model
  // transcribes the sound, not the numeral.
  assert.equal(value("loose rice arai kg"), 2.5);
  assert.equal(value("arai kg loose rice"), 2.5);
  assert.equal(value("der kg chini"), 1.5);
  assert.equal(value("adha kg dal"), 0.5);
});

test("common romanization variants of the same word", () => {
  for (const spelling of ["arai", "aarai", "adai", "aadai", "arhai"]) {
    assert.equal(value(`${spelling} kg rice`), 2.5, spelling);
  }
  for (const spelling of ["der", "derh", "dedh", "deed"]) {
    assert.equal(value(`${spelling} kg rice`), 1.5, spelling);
  }
});

test("prefix modifiers combine with the following number", () => {
  assert.equal(value("সাড়ে তিন কেজি চাল"), 3.5);
  assert.equal(value("সোয়া দুই কেজি"), 2.25);
  assert.equal(value("পৌনে চার কেজি"), 3.75);
});

test("prefix modifiers work romanized too", () => {
  assert.equal(value("sare tin kg rice"), 3.5);
  assert.equal(value("shoya dui kg"), 2.25);
  assert.equal(value("poune char kg"), 3.75);
});

test("prefix modifiers accept digits as the number", () => {
  assert.equal(value("sare 3 kg rice"), 3.5);
  assert.equal(value("সাড়ে ৩ কেজি"), 3.5);
});

test("half in English is half a unit", () => {
  assert.equal(value("half kg rice"), 0.5);
});

test("returns null when no fractional word is present, so an ordinary "
  + "quantity is never overridden", () => {
  assert.equal(value("2 kg rice"), null);
  assert.equal(value("দুই কেজি চাল"), null);
  assert.equal(value("loose rice"), null);
  assert.equal(value(""), null);
  assert.equal(value("3 pepsi and 2 packets of biscuit"), null);
});

test("a prefix with no number after it resolves to nothing rather than "
  + "guessing", () => {
  assert.equal(value("sare"), null);
  assert.equal(value("সাড়ে কেজি"), null);
  assert.equal(value("poune rice"), null);
});

test("matching is whole-token, so fractional words inside longer words do "
  + "not trigger", () => {
  assert.equal(value("dermatology cream"), null);
  assert.equal(value("araigarh brand rice"), null);
  assert.equal(value("halfway soap"), null);
});

test("case and surrounding punctuation do not matter", () => {
  assert.equal(value("ARAI kg rice"), 2.5);
  assert.equal(value("Der, kg chini"), 1.5);
  assert.equal(value("rice - arai kg."), 2.5);
});

test("reports which token matched, for the server log", () => {
  assert.equal(resolveSpokenQuantity("loose rice arai kg")?.matched, "arai");
  assert.equal(resolveSpokenQuantity("সাড়ে তিন কেজি")?.matched, "সাড়ে তিন");
});

test("the first fractional word wins when several appear", () => {
  // Multi-item speech resolved per item upstream; if two survive into one
  // string, the leading one is the one attached to this item.
  assert.equal(value("arai kg rice and der kg dal"), 2.5);
});

test("Bengali digits are understood after a prefix", () => {
  assert.equal(value("সোয়া ৪ কেজি"), 4.25);
  assert.equal(value("পৌনে ২ কেজি"), 1.75);
});

// --- resolveItemQuantity: what the Edge Function actually applies ------------

test("corrects the model's quantity when the item's own text carries a "
  + "fractional word", () => {
  const r = resolveItemQuantity({
    heard: "loose rice arai kg",
    transcript: "loose rice arai kg",
    modelQuantity: 2, // what Gemini actually returned for this sentence
    soleItem: true,
  });
  assert.equal(r.quantity, 2.5);
  assert.equal(r.corrected?.matched, "arai");
});

test("falls back to the whole transcript for a single item, because the model "
  + "often strips the amount out of `heard`", () => {
  const r = resolveItemQuantity({
    heard: "loose rice",
    transcript: "loose rice arai kg",
    modelQuantity: 2,
    soleItem: true,
  });
  assert.equal(r.quantity, 2.5);
});

test("does NOT consult the transcript when there are several items, since the "
  + "amount cannot be attributed to one of them", () => {
  const r = resolveItemQuantity({
    heard: "chini",
    transcript: "arai kg chal ar dui kg chini",
    modelQuantity: 2,
    soleItem: false,
  });
  assert.equal(r.quantity, 2);
  assert.equal(r.corrected, null);
});

test("rescues a quantity the model omitted entirely -- the case that reached "
  + "the app as an assumed 1", () => {
  const r = resolveItemQuantity({
    heard: "আড়াই কেজি খোলা চাল",
    transcript: "আড়াই কেজি খোলা চাল",
    modelQuantity: null,
    soleItem: true,
  });
  assert.equal(r.quantity, 2.5);
});

test("leaves an ordinary quantity untouched", () => {
  const r = resolveItemQuantity({
    heard: "pepsi",
    transcript: "2 pepsi",
    modelQuantity: 2,
    soleItem: true,
  });
  assert.equal(r.quantity, 2);
  assert.equal(r.corrected, null);
});

test("passes a missing quantity through as null when no fractional word is "
  + "present, so the app still flags it as assumed", () => {
  const r = resolveItemQuantity({
    heard: "pepsi",
    transcript: "pepsi",
    modelQuantity: null,
    soleItem: true,
  });
  assert.equal(r.quantity, null);
  assert.equal(r.corrected, null);
});

test("reports no correction when the model already got the fraction right, so "
  + "the log stays quiet", () => {
  const r = resolveItemQuantity({
    heard: "arai kg rice",
    transcript: "arai kg rice",
    modelQuantity: 2.5,
    soleItem: true,
  });
  assert.equal(r.quantity, 2.5);
  assert.equal(r.corrected, null);
});
