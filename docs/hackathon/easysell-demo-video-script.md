# EasySell: 5-minute demo video script

Topic E: SME Finance Copilot. The video states the problem, then shows the app
working on a real phone.

- **Length:** about 4 min 45 s, leaving a little room under the 5-minute limit.
- **Voiceover:** about 620 words, at a calm pace of about 135 words a minute.
- **Format:** each scene lists what is **on screen** and what to **say**.
  Record the phone screen first, then record the voiceover over it.

## Before you record

1. **Fill the app with demo data.** Paste `supabase/seed/demo_data.sql` into
   the Supabase SQL editor. It adds 55 products, five weeks of sales, a
   restock and four credit customers, so every screen looks full. Afterwards,
   `supabase/seed/remove_demo_data.sql` takes it out again.
2. **Redeploy the `money-tips` function**, so the AI advice no longer calls a
   tiny dip a "drop".
3. **Set up the phone:**
   - turn on Do Not Disturb
   - charge the phone fully
   - use the theme you like best (light or dark), the same one throughout
   - use the English language setting
4. **Record with Android's built-in screen recorder**, with sound on for the
   voice sale.
5. **Do the voice sale in a quiet room.**
6. **Keep products ready** for the camera scan, for example 2 or 3 items that
   are in the demo product list.

---

## Scene 1: The problem (0:00–0:40)

**On screen:** title card "EasySell: an AI finance copilot for neighbourhood
shops", then simple text slides: "21–26 million shops", "No real numbers",
"Warnings come too late", "US$5.7 trillion finance gap". Stock footage of a
corner shop works too.

**Say:**
> Across emerging markets, more than 20 million small neighbourhood shops sell
> everyday goods: kiranas in India, warungs in Indonesia, sari-sari stores in
> the Philippines, corner shops in Bangladesh.
>
> Most of them run on memory and a paper notebook. The owner doesn't really
> know their profit, how much customers owe them, or when cash is about to run
> out. They find out too late.
>
> And without records, a shop can't prove it can repay a loan. Small
> businesses in developing economies face a 5.7 trillion dollar financing
> gap.
>
> Bookkeeping apps exist, but they need typing at a busy counter, so most
> owners give up.

## Scene 2: The solution in one line (0:40–1:00)

**On screen:** the app opening on the Home dashboard.

**Say:**
> This is EasySell, an AI finance copilot for these shops. You sell by voice
> or by camera. EasySell keeps the records, watches your cash, warns you
> early, and shows which loans your shop is ready for. It covers all three
> parts of Topic E: financial analysis, cash-flow alerts, and financing
> matching.

## Scene 3: Selling by voice (1:00–1:40)

**On screen:**
1. Open Inventory and tap the mic.
2. Say a real sale out loud, for example "two Pepsi and one kilo of rice".
3. The cart fills with the matched items.
4. Choose a payment method (Cash, Digital or Credit).
5. Confirm. The success message appears.

**Say:**
> Selling takes one sentence. I tap the mic and say what I sold, in my own
> words.
>
> Gemini turns that sentence into cart lines, matched to this shop's own
> products. I can add a discount and pick how the customer paid: cash,
> digital or credit.
>
> Nothing is saved until I confirm. The AI suggests, the seller decides. When
> I confirm, the sale and the stock change are saved together, so the stock
> count is always right.

## Scene 4: Selling by camera (1:40–2:05)

**On screen:**
1. Tap the camera button.
2. Point at 2 or 3 products, tapping once for each.
3. The review tray fills with matched items.
4. Add them to the cart.

**Say:**
> Or I point the camera at the products and tap once for each one. Gemini
> recognises each item from the shop's list in the background, and they all
> land in one review tray. Ten items take about twenty seconds.

## Scene 5: Financial analysis (2:05–2:35)

**On screen:**
1. The Home dashboard: revenue, profit and margin. Switch between Today, Week
   and Month.
2. Tap a day on the sales chart.
3. Open Sales history and scroll. Tap one sale to show its detail.

**Say:**
> Every sale becomes real numbers. The dashboard shows revenue, profit and
> margin for today, this week or this month. I can tap any day on the chart
> to see what sold.
>
> Sales history keeps every sale with its items, amount and payment method,
> searchable by day.

## Scene 6: Money health and alerts (2:35–3:15)

**On screen:**
1. Scroll Home to the Money health card. Hold on money in, money out and net.
2. Show any warning that appears.
3. Open the full Money screen.

**Say:**
> This is Money health, the cash-flow part of the copilot. For the last seven
> days it shows money in, from cash and digital sales and customers paying
> back credit, money out for restocking, and what's left.
>
> Below it, EasySell watches for four problems: a customer more than thirty
> days late paying, restocking that costs more than the money coming in,
> credit owed growing fast, and sales falling sharply.
>
> These warnings come from fixed rules on the shop's real numbers, so they
> are always correct, and they're free to run.

## Scene 7: AI money advice (3:15–3:40)

**On screen:**
1. Tap "Get advice from EasySell AI".
2. The loading state shows, then 1–3 tips appear. Hold on them for 3 seconds.

**Say:**
> When I want advice, I tap once. Gemini turns these numbers into a few short
> tips in plain language, in the seller's own language.
>
> Our rule is simple: the rules decide, the AI only explains. The AI never
> calculates anything, so a tip can't contain a wrong number.

## Scene 8: Financing matching (3:40–4:15)

**On screen:**
1. On the Money screen, scroll to "Financing for your shop".
2. Show the four loan types, each with "Fits you" or "Not yet" and its reason.
3. Hold on one "Not yet" reason, for example "Keep trading 2 more months".

**Say:**
> This is financing matching. EasySell checks four kinds of loan, from
> supplier credit to a bank loan, against the shop's own last ninety days:
> how long it has traded, how steady its sales are, its profit margin, its
> digital payments, and the credit it's owed.
>
> Each one says "Fits you", with a rough amount, or "Not yet", with exactly
> what to do next. This demo shop is only five weeks old, so it sees "Not
> yet" and a clear path forward. These are examples for now. Next, we plan to
> connect real lenders, always with the owner's consent.

> **Note:** with five weeks of demo data every loan shows "Not yet", because
> even supplier credit needs 3 months of trading. The narration already says
> this, so it reads as the rules working, not as a fault.

## Scene 9: Everyday tools and trust (4:15–4:35)

**On screen:** quick cuts of about 3 seconds each:
1. the customer credit book
2. the restock planner
3. an expiry alert
4. the language switch to Bangla and back

**Say:**
> EasySell also keeps a credit book for each customer, tells the owner what
> to restock and how much, and warns before stock expires. It works in the
> shop's own currency and language. Each shop sees only its own data, and the
> app is backed by over seven hundred automated tests.

## Scene 10: Close (4:35–4:50)

**On screen:** the Home dashboard, then an end card with "EasySell",
"[Team name]" and "Topic E: SME Finance Copilot".

**Say:**
> EasySell turns everyday selling into a clear picture of the shop's money,
> and a path to the finance it needs. Thank you.

---

## Editing tips

- **Speed up the waits.** Cut or fast-forward the AI loading seconds (voice,
  scan, advice), but show the result clearly.
- **Add captions** for the voiceover. Many judges watch without sound or are
  not native English speakers.
- **Zoom in** on the key spots: the money in / out / net numbers, the
  warnings, the AI tips, and the "Fits you" / "Not yet" labels.
- **If you run long, trim** Scene 9 first, then Scene 4.
