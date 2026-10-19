# EasySell — project brief for the hackathon deck

Use this file to build the team's hackathon presentation deck. Everything here
is true of the working app as of 18 October 2026, and every market figure has
its source in section 10. Do not invent features, numbers, users or partners
that are not in this file.

## Instructions for the deck

- **Output: a PowerPoint file (.pptx), 16:9.**
- **Exactly 10 slides, never more.** A 10-minute pitch, about 1 minute per
  slide. Follow the outline in section 9 — it already fits everything in 10.
- **Must cover:** the **problem statement**, the **solution**, and the
  **business plan**.
- **Audience:** judges of an international fintech hackathon, **Track Topic E:
  SME Finance Copilot** ("a finance copilot for small-business owners,
  offering financing-option matching, cash-flow management with alerts, and
  business financial analysis").
- **Pitch it globally.** EasySell is for neighbourhood shops in emerging
  markets worldwide. Bangladesh is the **first launch market**, not the whole
  story. All money in **US dollars**.
- **Speaker notes on every slide:** what to say, about 100–130 words.
- **Style:** dark navy background with blue-to-violet accents (matches the
  app), large text, at most 5 short bullets per slide, one idea per slide,
  simple box-and-arrow diagrams for flows. Mark where app screenshots go, e.g.
  "[Screenshot: Money health card]".
- **Keep these placeholders as-is:** [Team name], [Member names and roles].
- **Honesty rules:** the financing options are *illustrative examples*, not
  real lender offers. No real shops have used the app yet: no claims of users,
  revenue or partners. Forecasts are plans, not guarantees.

---

## 1. One-line pitch

**EasySell: an AI finance copilot for the world's neighbourhood shops.** Sell
by voice or camera; the app tracks every sale, warns about money problems
early, and shows which loans the shop is ready for.

## 2. Problem statement

**Who:** the owners of small neighbourhood shops that sell everyday goods
across emerging markets — **about 21–26 million shops** in the six markets
sized: India's kiranas (12–13 million), Indonesia's warungs (3.9 million),
Bangladesh's corner shops (1–4.5 million), Africa's small independent shops
(2.5 million+), the Philippines' sari-sari stores (1.1–1.3 million) and
Mexico's tienditas (1.05 million).

**Their pain:**
1. **No real numbers.** Shops run on memory and a paper notebook. Owners rarely
   know their true profit, how much cash is stuck in stock, or how much
   customers owe them on credit.
2. **Money problems show up too late.** Unpaid customer credit piles up,
   restocking drains the cash drawer, and the owner only notices when there is
   no money for the next delivery.
3. **Locked out of finance.** Without records, a shop cannot prove it is
   creditworthy. Small businesses in emerging and developing economies face a
   **US$5.7 trillion financing gap**, plus about **US$2.1 trillion** more
   for informal businesses; women-owned businesses carry about a third of it
   (US$1.9 trillion) (IFC–World Bank).
4. **Existing apps don't stick.** Bookkeeping apps need typing at a busy
   counter, and many owners are not comfortable typing.

## 3. Solution: what EasySell does

**A. Sell fast with AI, so the records actually exist**
- **Voice sale:** the seller says what was sold in their own words; Gemini
  turns speech into cart lines.
- **Camera scan:** point the camera at products; Gemini vision matches them to
  the shop's own product list.
- **Checkout** with discount and payment method: **Cash / Digital / Credit**.
- The seller **confirms every AI result** before anything is saved.

**B. Business financial analysis**
- Dashboard: revenue, profit, margin and items sold for today / week / month,
  weekly sales chart, top seller; reports; searchable sales history.

**C. Cash-flow management with alerts: "Money health"**
- Last 7 days: **money in** (cash + digital sales + credit collected),
  **money out** (restocks), **net**.
- Four automatic warnings: a customer 30+ days late paying; restocks
  costing more than the money that came in; credit owed rising 20%+ in a
  week; sales down 25%+ from the week before.

**D. Financing-option matching**
- Four example loan types, from small to large: supplier credit,
  mobile-wallet small loan, microfinance shop loan, bank SME loan.
- Matched against the shop's **own** last 90 days: months trading, weeks
  with sales, profit margin, share of digital sales, credit owed.
- **"Fits you"** with the reason and a rough amount, or **"Not yet"** with
  what to do ("Keep trading 2 more months").

**E. AI copilot advice**
- One tap: Gemini turns the shop's numbers into 1–3 plain tips in the seller's
  language ("Ask Rahim to pay the 1,200 that is 34 days late").
- **Rules decide, AI words:** Gemini never calculates, so a tip cannot contain
  a wrong number. Called only on tap, cached for the day.

**F. Everyday shop tools**
- Customer credit book, restock planner (what to buy and how much, from
  selling speed), expiry tracking with daily reminders.

**Built for many countries:** the shop picks its own currency; every screen
uses translation files (English and Bangla today; a new language is one more
file); Gemini understands many languages, so voice selling can be extended to
new languages with testing.

## 4. How it meets Topic E

| Topic E asks for | EasySell feature |
|---|---|
| Financing-option matching | "Financing for your shop": 4 loan types matched to the shop's own records |
| Cash-flow management with alerts | "Money health": weekly in / out / net + 4 warnings |
| Business financial analysis | Dashboard, reports, sales history |
| A copilot | AI voice selling, camera scanning, and plain-language money advice |

## 5. Technology, trust and proof

- **Stack:** Flutter mobile app (Android, iOS-ready) · Supabase (PostgreSQL,
  Auth, Edge Functions) · Google Gemini, called only from the server.
- **Money math in the database, in one transaction:** a sale is never saved
  without its stock change; stock never goes negative; a lost network reply
  never records a sale twice; prices are frozen on each sale so past profit
  never changes.
- **Security:** Row Level Security on every table (each shop sees only its
  own data); no secret keys in the app; AI keys stay on the server; AI never
  saves anything without the seller's confirmation. A full security review
  found no exploitable vulnerabilities.
- **Proof it works:** working Android app tested on a real phone; **707
  automated tests passing**; about 27,000 lines of app code; 19 database
  migrations; 3 AI server functions; two languages.

Architecture (one diagram):

```
Seller ─voice/camera─► Edge Function ─► Gemini ─► suggested cart ─► seller confirms
                                                                       │
                                                                       ▼
                                   Database: record sale + stock in one transaction
                                                                       │
                                                                       ▼
          Money health + financing match (rules) ─► Gemini words the advice
```

## 6. Business plan

Full plan with sources: `docs/business/2026-10-18-easysell-international-business-plan.md`.

**Market**
- About **21–26 million** neighbourhood shops in six sized markets; total
  subscription market about **US$630 million a year** (21M × US$30).
- Our six target markets (Bangladesh, Philippines, Kenya, Nigeria, Indonesia,
  Mexico): **US$170–250 million a year** of smartphone-using shops.
- Year-3 goal of 25,000 paying shops is **under 0.5%** of that.
- **Why now:** mobile money passed **2.3 billion accounts and US$2 trillion**
  a year (GSMA, 2025); countries are pushing shops to digital payments; one
  AI-recorded sale now costs about **US$0.002**.

**Business model**
- **Free:** records, credit book, dashboard, **Money health alerts and
  financing matching** (rule-based, nearly free to run), so every shop
  enters the financing funnel.
- **Smart plan: US$2.99 a month list** (local prices lower; **average US$2.50**):
  up to 600 AI voice/camera sales a month + AI money advice.
- **Financing referral fees** (year 2+): a lender pays when a matched shop
  takes a loan with the owner's consent. *Assumption:* 2% of a US$500
  average loan. This is how leaders earn: Khatabook (~₹103 crore revenue,
  FY24) and BukuWarung earn from lending and payments, not bookkeeping alone.

**Unit economics (per paying shop, per month)**
- Contribution **US$1.48 (59%)** at typical use; **US$0.88 (35%)** even at the
  full AI allowance (after AI cost, a 15% app-store/payment fee and servers).
- Customer acquisition about **US$5** (assumption) → pays back in 3–4 months.
- Break-even: about 340 paying shops in year 1; about 17,000 at the year-3
  team size.

**Market entry**
1. **Year 1 — Bangladesh:** home market; Bangla QR mandate; voice-first fit.
2. **Year 2 — Philippines and Kenya:** sari-sari e-wallet surge; M-Pesa;
   less direct competition.
3. **Year 3 — Nigeria, Indonesia, Mexico:** gaps left by Kippa (app offline
   2024) and BukuKas (collapsed); 1.05M tienditas.
4. **Later — India:** largest but crowded; enter through a partner.

**Three-year forecast**

| | Year 1 | Year 2 | Year 3 |
|---|---|---|---|
| Markets | 1 | 3 | 6 |
| Paying shops (end of year) | 500 | 5,000 | 25,000 |
| Free users (end of year) | 10,000 | 100,000 | 500,000 |
| Revenue | US$7.5k | US$87.5k | US$490k |
| Profit / (loss) | (US$1.9k) | (US$69.8k) | (US$13.4k) |

Monthly profit by the end of year 3 (25,000 shops × US$1.48 ≈ US$37k a month
against US$25k fixed costs).

**Competition, one line each**
- Khatabook / OkCredit / Vyapar (India), BukuWarung (Indonesia),
  TallyKhata / Hishabee (Bangladesh): typing-based; EasySell leads with
  **voice and camera** plus **cash-flow alerts**.
- Lessons taken: Kippa and BukuKas failed on bookkeeping alone, so EasySell's
  revenue path is finance from day one.
- GrowSari (Philippines, 100,000 stores) and Tienda Pago (Peru): supply and
  credit players, potential partners.

**Funding ask: US$100,000 pre-seed** (cumulative loss to break-even about
US$85k + buffer): launch in Bangladesh, open the Philippines and Kenya, the AI
cost fix and offline selling, compliance. Plus introductions to lenders,
distributors and mobile operators.

**Risks → answers:** AI cost (send the AI fewer products, AI only in the paid
plan, hard allowance) · shops won't pay (free plan + lending revenue) · lender
fees lower than assumed (break-even on subscriptions alone at ~17,000 shops) ·
patchy internet (offline selling next) · AI mistakes (owner confirms every AI
sale) · data protection (consent before sharing with any lender).

**Impact:** includes owners who can't type; healthier, better-informed shops;
a path to finance, especially for women-owned businesses.

## 7. Team

[Team name] — [Member names and roles]. Three roles in the build: full-stack
app and backend; AI (Gemini prompts, voice and vision); device features and
quality assurance.

## 8. Roadmap

1. **"Ask EasySell" chat:** ask money questions in your own language.
2. **Real lender partners:** turn matches into applications, with consent.
3. **Shareable credit profile:** a one-page sales and repayment record for
   lenders.
4. **Offline selling** with automatic sync.
5. **New languages and currencies** for the next markets.

## 9. The 10 slides (do not add more)

1. **Title:** EasySell — AI Finance Copilot for the World's Neighbourhood
   Shops. [Team name] · Topic E: SME Finance Copilot.
2. **Problem statement:** 21–26 million neighbourhood shops across emerging
   markets; no real numbers, late cash warnings, locked out of a US$5.7
   trillion finance gap (a third of it women-owned); typing apps don't stick.
3. **Solution:** one picture — sell by voice/camera → app tracks the money →
   warns early → shows loans you're ready for.
4. **AI selling + financial analysis:** voice sale, camera scan, dashboard.
   [Screenshots: voice sheet, scan tray, dashboard]
5. **Money health + AI advice:** in / out / net, the 4 warnings, Gemini tips.
   [Screenshot: Money health card with AI advice]
6. **Financing matching:** "Fits you" / "Not yet" with reasons; Topic E
   coverage table. [Screenshot: Financing section]
7. **How it works, trust and proof:** architecture diagram; atomic sales;
   security; 707 tests, working app.
8. **Market and go-to-market:** market size (US$630M a year total, US$170–250M
   in our six target markets), why now (mobile money, cheap AI), entry order
   (Bangladesh → Philippines + Kenya → Nigeria, Indonesia, Mexico → India via
   a partner), competition and lessons in one line each.
9. **Business model and plan:** free + Smart plan (US$2.99) + financing
   referral fees; unit economics (US$1.48 a month, 59%); 3-year forecast table
   (500 → 5,000 → 25,000 paying shops, US$490k revenue in year 3, monthly
   profit by end of year 3); funding ask US$100,000 pre-seed.
10. **Roadmap, team and thank you:** next 5 steps, [Member names and roles].

## 10. Sources

- MSME finance gap (US$5.7 trillion formal + US$2.1 trillion informal, 119
  emerging and developing economies): [World Bank — SME Finance](https://www.worldbank.org/en/topic/smefinance);
  [SME Finance Forum — MSME Finance Gap](https://www.smefinanceforum.org/post/msme-finance-gap-report)
- India, about 12–13 million kirana stores: [Cornell SC Johnson — India's digital pull revolution](https://business.cornell.edu/article/2026/05/indias-digital-pull-revolution/);
  [Quartz](https://qz.com/india/1994922/why-amazon-and-reliance-need-indias-humble-kirana-stores)
- Philippines, about 1.1–1.3 million sari-sari stores: [The Ken](https://the-ken.com/story/the-uphill-battle-for-startups-to-win-over-filipino-neighbourhood-stores/);
  [Philippine News Agency](https://alpha.pna.gov.ph/opinion/pieces/838-sari-sari-stores-important-for-economic-growth)
- Indonesia, about 3.9 million warungs: [Jakarta Globe](https://jakartaglobe.id/business/end-of-an-era-modern-retail-leaves-indonesia-with-just-39-million-warung)
- Africa, 2.5 million+ small shops (Nigeria 600,000+, Kenya 250,000+): [BCG (2022)](https://www.bcg.com/publications/2022/the-future-of-traditional-retail-in-africa)
- Mexico, about 1.05 million tienditas: [Emprendedor, citing ANPEC](https://emprendedor.com/tiendita-emprendimiento-historia-mexico-comercio-tradicional/)
- Mobile money, 2.3 billion accounts and US$2 trillion in 2025: [GSMA](https://www.gsma.com/newsroom/?p=25651)
- Women-owned share of the gap (US$1.9 trillion, 34%): [World Bank — SME Finance](https://www.worldbank.org/en/topic/smefinance)
- Pricing, unit economics, forecast, competitors and all other sources: the
  team's international business plan
  (`docs/business/2026-10-18-easysell-international-business-plan.md`);
  Gemini prices from [Google's Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
