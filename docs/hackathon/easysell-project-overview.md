# EasySell: project overview

This file is for Claude Chat. Use it to help the team prepare hackathon
material, mainly the **5-minute demo video** about the problem and the app's
features. Everything here describes the working app as of 18 October 2026. Do
not invent features, users, partners or numbers that are not in this file.

## Instructions for Claude Chat

- **The hackathon:** an international fintech hackathon, **Topic E: SME
  Finance Copilot** ("a finance copilot for small-business owners, offering
  financing-option matching, cash-flow management with alerts, and business
  financial analysis"). The deadline is 20 October 2026, Beijing time.
- **The video:** 5 minutes at most. It states the problem, then shows the app's
  features on a real phone. The judges are international, so pitch globally.
  Bangladesh is only the first launch market.
- **Honesty rules:**
  - The financing options in the app are *illustrative examples*, not real
    lender offers.
  - No real shops use the app yet, so make no claims of users, revenue or
    partners.
  - The AI never calculates money. It only puts the app's own numbers into
    words.
- **Style:** plain words, short sentences, no jargon. Many viewers are not
  native English speakers.
- A draft script already exists: `easysell-demo-video-script.md`. Improve it
  rather than starting over, unless asked to.

---

## 1. What EasySell is

**EasySell is an AI finance copilot for neighbourhood shops.** A shop owner
sells by speaking or by pointing the camera. The app records every sale,
tracks the shop's money, warns the owner early about cash problems, and shows
which kinds of loan the shop is ready for.

- **Platform:** Android app (Flutter, iOS-ready), Supabase backend, Google
  Gemini AI on the server.
- **Languages:** English and Bangla today. Every screen uses translation
  files, so adding a language means adding one more file.
- **Currency:** the shop picks its own currency.
- **Look:** two themes, a light pastel-glass theme and a dark neon-glass theme.

## 2. The problem

**Who:** owners of small shops that sell everyday goods across emerging
markets. In the six markets we sized there are about **21–26 million** such
shops: India's kiranas, Indonesia's warungs, Bangladesh's corner shops,
Africa's small shops, the Philippines' sari-sari stores and Mexico's
tienditas.

**Their pain:**

1. **No real numbers.** Most shops run on memory and a paper notebook. Owners
   rarely know their true profit, how much cash is tied up in stock, or how
   much customers owe them.
2. **Money problems show up too late.** Unpaid customer credit grows, and
   restocking drains the cash drawer. The owner notices only when there is no
   money for the next delivery.
3. **Locked out of finance.** Without records a shop can't prove it can repay
   a loan. Small businesses in developing economies face a **US$5.7 trillion
   financing gap**, and about a third of it falls on women-owned businesses
   (IFC and World Bank).
4. **Existing apps don't stick.** Bookkeeping apps need typing at a busy
   counter, and many owners are not comfortable typing.

## 3. Features, as the user sees them

### A. Sell fast with AI, so the records actually exist

- **Voice sale:** tap the mic and say the sale in your own words, for example
  "two Pepsi and one kilo of rice". Gemini turns the sentence into cart lines
  matched to the shop's own products. You can edit a misheard sentence and send
  it again.
- **Camera scan:** point the camera at products and tap for each one. Gemini
  vision matches each photo to the shop's product list in the background. All
  results land in one review tray.
- **Cart and checkout:** a multi-item cart with an undo button, a flat
  discount, and a payment method of **Cash, Digital or Credit**. Credit sales
  go to a named customer.
- **The seller confirms every AI result** before anything is saved. The AI
  never records a sale on its own.
- **Safe money maths:** a sale and its stock change are saved together, or not
  at all. Stock can never go negative. If the network drops a reply, a retried
  sale is still recorded only once. Prices are frozen on each sale, so past
  profit never changes when prices change.

### B. Business financial analysis

- **Home dashboard:** revenue, profit, margin and items sold for today, this
  week or this month. It also has a weekly sales chart (tap a day to see that
  day's sales), the top-selling item, and cards for money owed, restocking and
  expiry.
- **Reports tab:** sales and profit over time.
- **Sales history:** every sale with its time, items, quantities, amount and
  payment method. You can search it, filter it by calendar day, and tap a sale
  to see its full detail.

### C. Money health: cash-flow management with alerts

A **Money health** card on Home opens a full Money screen.

- **The last 7 days:**
  - **money in:** cash and digital sales, plus credit customers paid back
  - **money out:** restocking
  - **net:** money in minus money out
- **Four automatic warnings:**
  1. A customer is **30+ days late** paying their credit. The warning names
     the biggest one.
  2. **Restocking cost more than the money that came in** this week.
  3. **Credit owed to the shop grew by 20% or more** in a week.
  4. **Sales fell by 25% or more** from the week before.
- The warnings come from fixed rules on the shop's real numbers, not from AI,
  so they are always correct and free to run.

### D. AI money advice ("Get advice from EasySell AI")

- One tap on the Money health card. Gemini turns the shop's numbers and
  warnings into **1–3 short tips** in the seller's language, for example "Ask
  Rahim to pay the 1,200 that is 34 days late".
- **Rules decide, AI words:** the app calculates everything first. Gemini only
  puts it into plain language, so a tip can't contain a wrong number.
- It runs only when tapped, and the result is kept for the day, so it costs
  almost nothing.

### E. Financing-option matching ("Financing for your shop")

- Four **example** loan types, from small to large:
  1. Supplier credit
  2. Mobile-wallet small loan
  3. Microfinance shop loan
  4. Bank SME loan
- Each is checked against the shop's **own last 90 days**: months trading,
  weeks with sales, profit margin, share of digital sales, and credit owed.
- Each type shows one of two results:
  - **"Fits you"**, with the reason and a rough amount
  - **"Not yet"**, with what to do, for example "Keep trading 2 more months",
    "Take more digital payments" or "Collect money owed"
- Matching options are listed first. The screen says clearly that these are
  examples, not offers.
- **Why it matters:** this turns everyday selling into a credit history and
  shows the owner a clear path to finance.

### F. Everyday shop tools

- **Customer credit book:** a running balance for each customer, with
  payments recorded.
- **Restock planner:** shows what to buy and how much, based on how fast each
  item sells over the last 4 weeks. Recent weeks count more, and out-of-stock
  days are skipped.
- **Expiry tracking:**
  - an expiry date for each delivery
  - in-app alerts and a daily phone reminder
  - expired stock is never sold by default
  - "Remove from stock" for thrown-away items, with a total of the money lost
- **Inventory:** products with photos, prices, stock and reorder levels.

## 4. How it meets Topic E

| Topic E asks for | EasySell feature |
|---|---|
| Financing-option matching | Financing for your shop: 4 loan types matched to the shop's own records |
| Cash-flow management with alerts | Money health: weekly in / out / net and 4 warnings |
| Business financial analysis | Dashboard, reports, sales history |
| A copilot | AI voice selling, camera scanning, plain-language money advice |

## 5. Trust and proof

- **Security:**
  - each shop can only ever see its own data (Row Level Security on every
    table)
  - no secret keys in the app; AI keys stay on the server
  - AI never saves anything without the seller confirming it
  - a full security review found no exploitable vulnerabilities
- **Proof it works:**
  - a working Android app, tested on a real phone (Samsung Galaxy S22)
  - **707 automated tests passing**
  - 19 database migrations and 3 AI server functions
  - two languages

## 6. Business model, in one paragraph

Records, alerts and financing matching are **free**, so every shop can join
and move towards finance. A **Smart plan at US$2.99 a month** (lower local
prices) adds up to 600 AI voice and camera sales a month, plus AI money
advice. From year 2, **lender referral fees** are earned when a matched shop
takes a loan with the owner's consent. Launch is in Bangladesh, then the
Philippines and Kenya, then Nigeria, Indonesia and Mexico. Full plan:
`docs/business/2026-10-18-easysell-international-business-plan.md`.

## 7. What's next

1. An "Ask EasySell" chat: ask money questions in your own language.
2. Real lender partners: turn a match into an application, with consent.
3. A shareable credit profile: a one-page sales and repayment record for
   lenders.
4. Offline selling with automatic sync.
5. New languages and currencies for the next markets.

## 8. Team

[Team name]: [Member names and roles]. The build had three roles: full-stack
app and backend; AI (Gemini prompts, voice and vision); device features and
quality assurance.
