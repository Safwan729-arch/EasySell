# EasySell: full project overview

This file is for Claude Chat. It describes the whole EasySell project as of
**19 October 2026**: the app, how it is built, the business plan, and where each
hackathon deliverable stands. Use it as the single source of truth when helping
the team. **Do not invent features, users, partners or numbers that are not in
this file.**

## Instructions for Claude Chat

- **The hackathon:** an international fintech hackathon, **Topic E: SME Finance
  Copilot** ("a finance copilot for small-business owners, offering
  financing-option matching, cash-flow management with alerts, and business
  financial analysis"). **Deadline: 20 October 2026, Beijing time.**
- **Audience:** international judges. Pitch globally; Bangladesh is only the
  first launch market. Money in US dollars.
- **Honesty rules:**
  - The loan types in the app are **illustrative examples**, not real lender
    offers. No lender is connected.
  - **No real shops use the app yet.** Make no claims of users, revenue or
    partners.
  - The AI never calculates money. It only puts the app's own numbers into
    words.
  - Business forecasts are plans built on stated assumptions, not guarantees.
- **Style:** plain words, short sentences, no jargon. Many readers are not
  native English speakers.
- **Placeholders to keep as-is:** [Team name], [Member names and roles],
  [GitHub link].

---

## 1. Hackathon deliverables and their status

| Deliverable | Required? | Status |
|---|---|---|
| Technical documentation | Mandatory | **Done.** A Claude Doc, "EasySell: Technical Documentation", with architecture and data-model diagrams, 10 screenshot panels, project structure, restock maths, expiry and batch selection, security, testing, setup, limitations and future plans |
| Presentation deck (10 slides, 10-minute talk) | Mandatory | **Done, version 2.** `EasySell_Hackathon_Deck_v2.pptx` and `.pdf`. Real app screenshots on slides 4–6; numbers corrected to match the app. [Team name] placeholders still to fill. Three business-side fixes are pending (Section 11) |
| Demo video (up to 5 min) | Optional | Script drafted: `docs/hackathon/easysell-demo-video-script.md`. Not recorded yet |
| Source code with README and GitHub link | Optional | Code is on GitHub: [GitHub link] |
| Security self-assessment report | Optional | Not written as a separate report. The material exists: a full review on 19 October (Section 8) |
| Execution evidence | Optional | Not prepared yet. Proposed contents in Section 12 |

---

## 2. What EasySell is

**EasySell is an AI finance copilot for neighbourhood shops.** The owner sells
by speaking or by pointing the camera. The app records every sale, tracks the
shop's money, warns early about cash problems, and shows which kinds of loan the
shop is ready for.

- **One-line pitch:** "AI Finance Copilot for the World's Neighbourhood Shops.
  Sell by voice or camera. EasySell tracks every sale, warns about money
  problems early, and shows which loans the shop is ready for."
- **Platform:** Android app (Flutter; the code is ready for iOS but not built or
  tested there). Backend on Supabase. Google Gemini AI runs on the server only.
- **Languages:** English and Bangla (with Bengali digits). Switchable in
  Settings.
- **Currencies:** US dollar and Bangladeshi taka today. Each shop stores its
  own currency.
- **Look:** dark navy "neon glass" design (a light theme also exists).
- **Version:** 1.1.0 (build 2). Tested on a Samsung Galaxy S22.

## 3. The problem

**Who:** owners of small shops that sell everyday goods across emerging
markets: about **21–26 million shops** in the six regions sized: India's kiranas
(12–13M), Indonesia's warungs (3.9M), Bangladesh's corner shops (1–4.5M),
Africa's small shops (2.5M+), the Philippines' sari-sari stores (1.1–1.3M) and
Mexico's tienditas (1.05M).

**Their pain:**

1. **No real numbers.** Memory and a paper notebook. Owners rarely know true
   profit, cash stuck in stock, or credit customers owe them.
2. **Warnings come late.** Unpaid credit piles up and restocking drains the
   drawer. The owner notices only when there is no cash for the next delivery.
3. **Locked out of finance.** No records means no proof of creditworthiness.
   Small businesses in emerging economies face a **US$5.7 trillion financing
   gap**; women-owned businesses carry about a third of it (US$1.9 trillion)
   (IFC–World Bank).
4. **Typing apps don't stick.** Bookkeeping apps need typing at a busy counter,
   and many owners are not comfortable typing.

## 4. Features, as the user sees them

### 4.1 Selling with AI (so the records exist)

- **Voice sale:** tap the mic and say the sale, for example "two Pepsi and one
  kilo of rice". The recording and the shop's product list go to the
  `parse-sale` function. Gemini writes down what was heard and matches each item
  to a product. The owner reviews the matched items, can edit the heard
  sentence and resend, then adds them to the cart. There is also a "type it
  instead" option.
- **Camera scan:** point the camera at products and tap once per item. Each
  photo goes to the `recognize-product` function, and Gemini matches it to the
  shop's product list. Results collect in one review tray. If two products look
  alike (Pepsi 500 ml and 1 L), both are shown and the owner picks.
- **Checkout:** a multi-item cart with undo, a flat discount, and a payment
  method: **Cash, Digital or Credit** (credit goes to a named customer). One tap
  saves the whole sale.
- **Nothing from the AI is saved until the owner checks it and taps
  checkout.**

### 4.2 Business financial analysis

- **Home dashboard:** revenue, profit, margin and items sold for today, this
  week or this month (or a picked day), a 7-day sales chart (tap a day), the top
  seller, and cards for money owed and Money health.
- **Reports tab:** best sellers and sales by category for the chosen period.
- **Sales history:** every sale with items, amount and payment method; search
  and filter by day; tap to open the full receipt.
- All totals are summed inside the database, so the phone only displays
  numbers.

### 4.3 Money health (cash-flow management with alerts)

- **Last 7 days:** money in (cash and digital sales, plus credit customers paid
  back), money out (restocking), and net.
- **Four automatic warnings:**
  1. A customer is **30+ days late** paying credit (oldest unpaid credit counts
     first; the warning names the biggest debtor).
  2. **Restocking cost more** than the money that came in this week.
  3. **Credit owed grew 20%+** in a week.
  4. **Sales fell 25%+** from the week before.
- Warnings are fixed rules on real records: exact and free to run. No AI.

### 4.4 AI money advice ("Get advice from EasySell AI")

- One tap sends the app's already-calculated numbers and warnings to the
  `money-tips` function. Gemini turns them into **1–3 short tips** in the
  owner's language.
- **Real example from the demo shop:** "Collect the ৳7,402 in credit owed now
  before it gets old to keep your cash flow strong." Every amount in a tip is
  copied from the card's numbers.
- Runs only on tap; the answer is saved on the phone for the day. Under the
  tips: "Based on the numbers above. Check them before you act."

### 4.5 Financing matching ("Financing for your shop")

- Four **example** loan types, small to large: supplier credit, mobile-wallet
  small loan, microfinance shop loan, bank SME loan.
- Each is checked against the shop's **own last 90 days**: months trading,
  weeks with sales, profit margin, share of digital sales, credit owed.
- Result: **"Fits you"** with a rough amount, or **"Not yet"** with the next
  step ("Keep trading 2 more months"). The screen says these are examples, not
  offers.
- The demo shop has five weeks of data, so every option shows "Not yet".

### 4.6 Restock planner: what to buy and how much

Pure arithmetic on the shop's own records, no AI.

1. **Sales speed:** the database looks at the last 28 full days in 4 weeks.
   Weekly rate = units sold ÷ days the item was actually in stock (days with an
   empty shelf, or only expired stock, are skipped, so a sold-out item doesn't
   look slow).
2. **Recent weeks count more:** speed = 0.4 × last week + 0.3 × week 2 + 0.2 ×
   week 3 + 0.1 × week 4 (divided by the weights of weeks that had stock).
3. **Good stock** = stock on the shelf − expired units.
4. **Days left** = good stock ÷ speed.
5. **Buy** = speed × (restock days + 2 extra days) − good stock, rounded up.
   The owner sets restock days (1–30, default 7). Example: 5 a day × (7 + 2) −
   10 left = **buy 35**.
6. An item at or below its **reorder level** is always "Buy now", with enough to
   get back above it.
7. Sorted by days left; red if it runs out within 2 days; arrows show if sales
   are rising or falling (last week vs. speed, ±20%).

Limit: it assumes the coming days sell like the last 4 weeks; it can't foresee
holidays.

### 4.7 Expiry tracking and batch selection

- Each **delivery (batch)** can have its own expiry date.
- The app estimates what is left of each delivery: oldest sells first, except
  units the owner picked from a named batch at checkout.
- Status: **Good**, **Expiring soon** (the shop's warning window, 3/7/14/30
  days, default 7; shorter for short-life items, e.g. 5-day bread warns 1 day
  before), **Expired** (locked: can't be sold, not counted as stock).
- Alerts in the app ("Expiring" filter), a daily phone reminder at 9 AM, and
  "Remove from stock" that records the loss.
- **Batch choice in the cart:** if an item can come from two or more
  deliveries, the cart shows "Batch: Choose" and **Checkout stays off** until
  the owner picks. The list shows deliveries soonest-expiry first with units
  left; expired ones never appear. "Several batches, soonest expiry first"
  splits a line when no single batch has enough. Expired stock can't even be
  added to the cart ("5 pcs expired — not counted").
- The server checks the chosen batch in the same transaction as the sale and
  refuses one that is expired or used up.

### 4.8 Other everyday tools

- **Customer credit book:** running balance per customer, ledger of credit
  sales and payments, record a payment.
- **Inventory:** products by piece, weight or volume; prices; stock; reorder
  levels; categories; archive.

## 5. How it meets Topic E

| Topic E asks for | EasySell feature |
|---|---|
| Financing-option matching | Financing for your shop: 4 loan types matched to the shop's own records |
| Cash-flow management with alerts | Money health: weekly in / out / net + 4 warnings |
| Business financial analysis | Dashboard, Reports, Sales history |
| A copilot | Voice and camera selling, plain-language AI money advice |

## 6. Technology

| Layer | Technology |
|---|---|
| App | Flutter 3.44 (Dart), Material 3, Riverpod 3, go_router 17, fl_chart |
| Backend | Supabase: PostgreSQL, Auth (email + password), Edge Functions |
| Server logic | Postgres functions (PL/pgSQL); every money change is one database transaction |
| AI functions | 3 Supabase Edge Functions (Deno, TypeScript): `parse-sale`, `recognize-product`, `money-tips` |
| AI models | Gemini 3.5 Flash-Lite (voice); Gemini 3.6 Flash (camera, advice) |
| Device | camera, record (audio), flutter_local_notifications |
| Languages | Flutter localisation files (English, Bangla) |

**Architecture:** the app talks only to Supabase. Supabase holds the data,
checks who is signed in, and calls Gemini. The Gemini key never reaches the
phone.

```
Seller (voice / camera) → Edge Function → Gemini → suggested cart → seller confirms
                                                                      ↓
                                  Database: record sale + stock in ONE transaction
                                                                      ↓
                  Money health + financing match (rules) → Gemini words the advice
```

**Data:** 10 tables (8 in use), built by 20 migration files. Every business row
belongs to one shop. One receipt = several `transactions` rows sharing a
`sale_group_id`.

**Size:** about 27,000 lines of app code, 15,000 lines of tests, 3,500 lines of
SQL, 1,200 lines of server functions. 34 design notes in `docs/`.

## 7. AI design and safeguards

**Rule: the rules decide, the AI only puts things into words.**

- **Fixed output shape:** every call asks Gemini for strict JSON.
- **Replies are checked:** the server drops product IDs not in the shop's list,
  limits confidence to 0–1, keeps at most 3 tips.
- **The owner confirms** every voice and camera result.
- **No invented numbers:** advice gets every amount pre-formatted; the prompt
  forbids changing or adding numbers.
- **Speed and cost limits:** output token caps, 15–20 second time limits;
  advice only on tap, cached per day.
- **Bangla number words** (e.g. আড়াই = 2.5) are corrected by fixed code after
  Gemini replies.

## 8. Reliability and security

**Money data:**

- **Atomic checkout:** one function locks each product row, checks stock,
  lowers it, saves the sale lines, splits the discount and records credit.
  If one line fails, nothing is saved.
- **Stock never goes below zero:** a database rule plus row locks.
- **Frozen prices:** each sale line stores that moment's buying and selling
  price, so past profit never changes.
- **Safe retries:** the phone creates an ID for every sale, restock, stock
  removal and credit payment; the server records each ID once.
- **Exact discounts:** the split always adds up to the discount entered.
- **Local days:** "today" follows the shop's own midnight, not UTC.
- **Credit balance is always summed** from the ledger, never stored.

**Security measures:** Row Level Security on all 10 tables (a shop sees only its
own rows); all app functions run with the user's own rights; only the public
Supabase key is in the app; the AI functions accept only signed-in, non-guest
users (others get 401) and refuse oversized requests (413); guest sign-in is
off; no SQL built from user text; Android backup and phone-to-phone transfer
are off.

**Security review, 19 October 2026:** every migration, function and money path
was reviewed, then the live system was tested from outside with only the public
key: every table returned 0 rows, the AI functions refused the key, and another
shop's ID returned nothing.

- **Fixed in the review:** the AI functions accepted the public key; dashboard
  days were cut at UTC midnight; credit payments were not safe to retry; guest
  sign-in was on; a language check in `money-tips` could be tricked.
- **Open before a public launch:** release builds signed with the debug key;
  email confirmation is off for the demo; no daily per-user AI limit; owners
  can edit their own sale rows directly (matters once lenders rely on them);
  the top debtor's name is sent to Gemini (needs a privacy notice).

## 9. Testing and proof

- **715 automated tests in 126 test files, all passing**; the Dart analyzer
  reports no issues.
- Logic tests (money rules, warnings, financing, discount split, restock,
  expiry), screen tests (checkout, cart, voice review, scan tray, history,
  Money health, payment sheet), Deno tests for the Bangla number correction.
- Database changes were run on a real Postgres engine (PGlite) before release;
  the latest migration passed 18 checks.
- Every feature tested on a Samsung Galaxy S22 with a demo dataset (55
  products, five weeks of sales, four credit customers).

## 10. Business plan (summary)

Full plan with sources:
`docs/business/2026-10-18-easysell-international-business-plan.md`.

- **Market:** about 21–26M shops; total subscription market about **US$630M a
  year** (21M × US$30); our six target markets (Bangladesh, Philippines, Kenya,
  Nigeria, Indonesia, Mexico) about **US$170–250M a year**; the year-3 goal of
  25,000 paying shops is under 0.5% of that.
- **Why now:** mobile money reached 2.3 billion accounts and over US$2 trillion
  in 2025 (GSMA); Bangladesh made Bangla QR compulsory for merchants on 1 July
  2026; AI is cheap enough to sell for a few dollars a month.
- **Plans:**
  - **Free (US$0):** records, credit book, dashboard, Money health alerts,
    financing matching.
  - **Smart (US$2.99/month list, about US$2.50 average with local prices):**
    up to 600 AI sales a month + AI money advice.
  - **Lender referral fees (year 2+):** about 2% of a loan (assumed US$500
    average), with the owner's consent.
- **Unit economics per paying shop per month:** US$2.50 − AI US$0.60 − store
  fee US$0.38 − servers US$0.05 = **US$1.48 (59%)**; US$0.88 (35%) at full AI
  use. Acquisition about US$5 (assumption), paid back in 3–4 months.
- **Entry order:** Bangladesh (year 1) → Philippines + Kenya (year 2) →
  Nigeria, Indonesia, Mexico (year 3) → India later, through a partner.
- **Competition:** Khatabook, OkCredit, Vyapar, BukuWarung, TallyKhata,
  Hishabee are typing-based; EasySell leads with voice, camera and cash-flow
  alerts. Lesson from Kippa and BukuKas: bookkeeping alone doesn't pay, so
  finance is the revenue path from day one.

| | Year 1 | Year 2 | Year 3 |
|---|---|---|---|
| Markets | 1 | 3 | 6 |
| Paying shops (end) | 500 | 5,000 | 25,000 |
| Free users (end) | 10,000 | 100,000 | 500,000 |
| Revenue | US$7.5k | US$87.5k | US$490k |
| Profit / (loss) | (US$1.9k) | (US$69.8k) | (US$13.4k) |

- **Funding ask (current deck): US$100,000 pre-seed.**

## 11. Known issues in the business numbers (fix before submitting)

A check on 19 October found the maths and outside statistics correct, except:

1. **The funding ask looks too small.** The plan says US$100k covers "the
   cumulative loss to break-even (about US$85k)". But US$85k is the total at the
   *end* of year 3, after profits start. Modelled month by month from the plan's
   own assumptions, the first profitable month is **month 7 of year 3** and the
   **lowest cash point is about US$119k**. Suggested fix: ask for about
   **US$125,000**, or keep US$100k and hire more slowly in year 3. (Team has not
   decided yet.)
2. **"One AI-recorded sale now costs about US$0.002"** assumes a planned fix
   (send Gemini about 60 likely products instead of the whole list). The app
   still sends the whole list, and camera scans use the dearer Gemini 3.6 Flash,
   whose price doubles on 1 January 2027. Suggested wording: "about US$0.002
   once a planned prompt fix is built".
3. **"Six markets" means two different lists** (slide 2 includes India and
   Africa; slide 8 is the six target countries). Suggested: call slide 2's list
   "six regions we sized".

## 12. Proposed execution evidence (not built yet)

Most convincing first: (1) measured AI accuracy, speed and real cost per sale
on ~20 voice sentences in English and Bangla and ~15 photos; (2) money-safety
proof: two sales for the last item at once (one refused), a retried sale saved
once; (3) the outside security test output; (4) a fresh dated test run; (5) a
screen recording of one full sale on the phone; (6) the development timeline
and design notes; (7) deployment proof; (8) honest limits.

## 13. Limitations today

- Loan types are examples; no lender connected.
- "Money out" counts restocking only (no rent, wages or other costs yet).
- Every sale needs internet.
- Android only.
- Two languages and two currencies.

## 14. Future plans

1. **"Ask EasySell" chat** for money questions in the owner's language.
2. **Real lender partners:** turn "Fits you" into an application, with consent.
3. **Shareable credit profile:** a monthly PDF report for lenders.
4. **Export data as a file:** sales, stock and credit as CSV (Excel), plus the
   monthly PDF report, shared through Android's share menu. Designed, not built.
5. **Offline mode:** save sales on the phone first, keep products and customers
   on the phone, sync to Supabase when back online (Supabase stays the main
   copy). Part done: sale IDs come from the phone, so a sale sent twice is saved
   once.
6. **More languages and currencies** for the Philippines, Kenya, Nigeria,
   Indonesia and Mexico (one translation file per language; one entry per
   currency).
7. Record other expenses so "money out" is complete.

## 15. Team

[Team name]: [Member names and roles]. Three build roles: full-stack app and
backend; AI (Gemini prompts, voice and vision); device features and quality
assurance.

## 16. Key files

| File | What it is |
|---|---|
| `docs/hackathon/easysell-project-overview.md` | This file |
| `docs/hackathon/easysell-project-brief.md` | Brief used to build the deck (dated 18 Oct; some figures now superseded by this file) |
| `docs/hackathon/easysell-demo-video-script.md` | Draft demo video script |
| `docs/business/2026-10-18-easysell-international-business-plan.md` | Full business plan with sources |
| `docs/superpowers/specs/2026-10-19-codebase-review-fixes-design.md` | Security and bug review |
| `docs/00-Map.md` | Index of all 34 design notes |
| `Downloads/EasySell_Hackathon_Deck_v2.pptx` / `.pdf` | Current deck |

## 17. Sources for outside figures

- Finance gap (US$5.7T; women-owned US$1.9T, 34%): [SME Finance Forum](https://www.smefinanceforum.org/news/11541348)
- Mobile money (2.3B accounts, over US$2T in 2025): [GSMA via AAP](https://www.aap.com.au/aapreleases/cision20260324ae16820/)
- Bangla QR compulsory from 1 July 2026: [TBS](https://www.tbsnews.net/node/1472346)
- Gemini prices: [Google — Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- Shop counts and competitors: see the business plan's Sources section.
