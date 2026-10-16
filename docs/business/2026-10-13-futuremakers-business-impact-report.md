# AI Shopkeeper Assistant — Social Impact & Business Report

**Prepared for:** GP FutureMakers 2026 — *"AI for Social Good"*
**Date:** 13 October 2026
**Product status:** working Android app (Flutter) on a live Supabase backend, with Gemini AI for Bangla voice and camera selling. Tested internally; no external pilot yet.

> All money figures are in Bangladeshi Taka (৳) at **৳123 = US$1** (Bangladesh Bank reference rate, July 2026). AI costs are **estimates** built from the app's actual code and Google's published prices. Each calculation states its assumptions so a judge can check it.

---

## 1. Summary

Bangladesh's neighbourhood *mudi dokans* still run on a paper khata. Stock is counted by eye, nobody knows the day's real profit, and *baki* (customer credit) is a column of pencil marks that is hard to total and easy to dispute. Free digital khata apps exist. But they expect the shopkeeper to **type**, and **42% of Bangladeshis are below fifth-grade literacy**.

**AI Shopkeeper Assistant lets a shopkeeper make a sale by speaking Bangla or by pointing the camera at the goods.** Behind that, it keeps stock, profit and customer credit correct automatically. A spoken sentence like *"আড়াই কেজি চাল আর দুইটা পেপসি"* ("two and a half kilos of rice and two Pepsis") becomes a checked sale. Stock falls, profit is recorded, and the customer's baki updates if it was a credit sale.

| | |
|---|---|
| **Social problem** | Low-literacy, low-margin shopkeepers (many of them women) can't use typing-heavy tools. Without records they can't see profit, manage stock, collect baki or show a lender any history |
| **Our answer** | Voice-first, camera-first AI bookkeeping in Bangla. The AI only *suggests*; the shopkeeper confirms every sale |
| **Market** | 1–4.5 million small shops (estimates vary); 73.4% of households own a smartphone; Bangla QR became mandatory for merchants in July 2026, so shops are being pushed to go digital right now |
| **Business model** | Free core app, plus a paid **Smart plan (৳299/month)** for AI voice and camera, then sponsored and lending partnerships |
| **Unit economics** | About ৳0.20 of AI cost per voice or camera sale after one planned optimisation, which gives a ~55% contribution margin. **Break-even at ~150 paying shops** |
| **FutureMakers fit** | Digital access & education (primary); gender equality & inclusion; skills & jobs; safety, security & data privacy |

---

## 2. The problem

### 2.1 Who we serve

The **mudi dokan**, a 100–200 sq ft neighbourhood grocery holding 500–1,000 different items ([Khulna grocery study](https://www.researchgate.net/publication/374000317_Inventory_Management_Techniques_for_Grocery_Shops_in_Bangladesh_A_Study_on_a_Grocery_Shop_in_Khulna_City)). These shops carry almost all of Bangladesh's everyday consumption.

- ShopUp estimates **4.5 million small shops account for 98% of consumption** ([Dhaka Tribune](https://www.dhakatribune.com/business/281651/shopup-secures-30m-debt-financing-to-fuel)). This is a company estimate.
- The **Economic Census 2024** counted **11.70 million economic units**, with wholesale & retail trade (plus vehicle repair) the largest group at **41.82%** ([UNB](https://unb.com.bd/category/Bangladesh/economic-census-2024-report-released-economic-units-grew-nearly-50-in-a-decade/183102)).
- Older sector estimates put grocery shops alone at **about 1 million** ([industry overview](https://www.scribd.com/document/139715168/Bangladesh-retailing-industry)).

There is no official count of grocery shops alone, so this report uses **1–4.5 million** as the range.

### 2.2 What goes wrong today

| Pain | Consequence |
|---|---|
| **No stock record** | Shopkeepers find out an item is gone when a customer asks for it, and over-order slow sellers. Working capital is tied up in the wrong goods |
| **No profit visibility** | Margins are thin (around 3–4% net at small retail shops in one study). A shop can be busy and still lose money without noticing |
| **Paper baki** | Credit given to neighbours is hard to total and easy to dispute. Money owed quietly goes uncollected |
| **No financial history** | Banks lend on records and collateral. **More than 60% of micro-enterprises cannot access credit**, and those that can often pay **24–40% interest** ([TBS](https://www.tbsnews.net/thoughts/digital-lending-small-businesses-and-merchants-513798)) |
| **Typing is a barrier** | **42.45% of people are below fifth-grade literacy** ([Bonik Barta, HMSS 2025](https://en.bonikbarta.com/bangladesh/c2Aj8lzZeMef4q32)); functional literacy is **62.92%** ([Prothom Alo, BBS](https://en.prothomalo.com/bangladesh/c7axno0vhh)). Apps that need typing leave out the shopkeepers who need help most |

### 2.3 Women are hit hardest

Women-led enterprises hold only **7.28% of small-business loans**, against Bangladesh Bank's **15% target**, as of March 2026 ([Dhaka Tribune](https://www.dhakatribune.com/business/banks/417380/gender-disparity-rising-in-sme-finance)). The reasons are collateral rules (few women hold property titles) and paperwork such as audited statements. A clean digital sales history is the kind of record that can replace some of that paperwork.

---

## 3. The solution: what the app does today

Everything in this section is **built and tested** (443 automated tests passing).

### 3.1 AI features: the core of the social case

| Feature | What the shopkeeper does | Why it matters socially |
|---|---|---|
| **Voice sale (Bangla, English, Banglish)** | Says the sale out loud, e.g. *"arai kg khola chal, dui ta pepsi"*. The AI turns it into items, quantities and products | No typing. Understands Bengali fraction words such as আধা (½), দেড় (1½), আড়াই (2½), সাড়ে, সোয়া and পৌনে, and checks them in code so a spoken "2½ kg" is never recorded as "2 kg" |
| **Camera scan session** | Points the camera at the items and taps once per item. Recognition runs in the background, and everything is reviewed in one tray | A ten-item basket goes from about **40 taps / 75 seconds** in the old one-photo-at-a-time flow to about **11 taps / 20 seconds** (our design estimate, to be confirmed in the pilot). That's faster checkout with no typing |
| **AI never decides alone** | Every AI result appears on a confirmation screen before anything is saved | Protects shopkeepers from AI mistakes. Required by our own design rules |
| **Smart tie-breaking** | If "Pepsi" could mean 500 ml or 1 L, the app asks, or leans towards the one this shop actually sells most | Fewer wrong sales, and less frustration for low-literacy users |

### 3.2 Bookkeeping features

- **Inventory:** products with categories, units (pieces, kg, g, litre, ml), buying and selling prices, archived products, and the total value of stock.
- **Cart and checkout:** several items per sale, cash or **baki (credit)**, and a flat discount.
- **Stock can never go wrong:** each sale updates stock and records the sale in one step on the server, so stock can't go negative and a sale can't be half-saved.
- **True profit:** each sale freezes the buying and selling price at that moment, so past profit stays correct when prices change.
- **Customer khata:** a running credit ledger per customer, recording payments, showing who owes what, and a total for money owed to the shop.
- **Dashboard and reports:** today's and weekly revenue and profit, trend charts, a breakdown for any day, and payment-method splits.
- **Sales history:** a calendar filter and full details of every past sale.
- **Full Bengali interface:** an in-app language switch, Bengali numerals and a Bengali font.
- **Privacy by design:** each shop can only ever see its own data, enforced by the database itself (Row Level Security).

### 3.3 Not built yet (stated honestly)

| Gap | Status |
|---|---|
| **AI insights & trends screens** | The screens exist, but the AI that writes the insights was never built. Roadmap |
| **Working offline** | Every sale currently needs internet. The app shows a "no internet" banner but can't record a sale offline. **This is the most important gap** (see §8) |
| **Bangla QR / bKash payment recording** | Not built. Roadmap |
| **Low-stock push notifications** | Not built |

---

## 4. Market analysis

### 4.1 Market size

| Layer | Estimate | Basis |
|---|---|---|
| **Total market** | **1–4.5 million** small shops | Range of the published estimates in §2.1 |
| **Reachable now** | **~2–3 million** | Shop owners with a smartphone and mobile internet: **65.6%** of individuals own a mobile phone and **73.4%** of households own a smartphone ([UNB/BBS](https://unb.com.bd/category/Bangladesh/mobile-phone-ownership-rises-bbs/195830), [Dhaka Tribune/BBS](https://www.dhakatribune.com/bangladesh/415972/bbs-survey-over-57%25-of-bangladeshi-households-now)); **135.9 million** internet subscriptions in June 2026 ([Financial Express/BTRC](https://thefinancialexpress.com.bd/trade/internet-subscriber-growth-outpaces-mobile-connections-in-h1)) |
| **3-year target** | **10,000 paying shops** | About 0.3–0.5% of reachable shops. Deliberately modest for a student-founded venture |

### 4.2 Why now

1. **Bangla QR became mandatory on 1 July 2026.** Every merchant must accept QR payments, and **2.4 million merchants** were registered by August ([Observer/Bangladesh Bank](https://observerbd.com/news/586785)). Shopkeepers are being pushed into digital tools now.
2. **Smartphones are already in most shops.** Household smartphone ownership is 73.4%.
3. **AI is now cheap enough.** A voice sale costs about **৳0.2–0.3** in AI fees (§6). Two years ago this product would not have been affordable.
4. **A new data law makes trust a selling point.** The **Personal Data Protection Ordinance 2025** sets consent and data-handling rules ([Daily Star](https://www.thedailystar.net/tech-startup/news/bangladeshs-personal-data-protection-ordinance-2025-key-takeaways-4015401)). Shops will prefer tools that are built to comply.

### 4.3 Competitors

| Competitor | What they offer | Strength | Where we differ |
|---|---|---|---|
| **TallyKhata** (Progoti Systems) | Free digital khata, sales/stock records, TallyPay wallet, QR payments | **1 crore+ downloads**, about 1M monthly users, **works offline**, central-bank-licensed wallet ([TallyKhata](https://www.tallykhata.com/million-shopkeepers-using-tallykhata-app-for-records-and-payments/)) | Built around typing. No AI voice or camera selling |
| **Hishabee** | POS, inventory, accounting, **inventory finance up to ৳50,000** through Prime Bank | 300,000+ businesses (homepage); claims 1M+ merchants reached ([Hishabee](https://hishabee.io), [Impact Report](https://www.hishabee.io/impact)) | Typing-based POS. We add voice and camera, and could integrate rather than compete |
| **ShopUp / Mokam** | B2B supply to shops plus "Baki" stock credit | Large distribution network, $30M debt financing ([TBS](https://www.tbsnews.net/dropped/startups/shopup-secures-30m-debt-financing-boost-expansion-supply-chain-578646)) | A supply business, not shop bookkeeping. A possible partner |
| **Hishab / Verbex.ai** | Bangla voice AI over phone calls | Backed by Startup Bangladesh (৳2 crore) ([Startup Bangladesh](https://www.startupbangladesh.vc/startup-bangladesh-invests-in-hishab-telephony-driven-generative-ai/)) | Enterprise call automation, not a shop app. Shows that Bangla voice AI is investable |
| **Paper khata** | Notebook | Free, universal, trusted | No totals, no profit, no history |

**Our position:** *the shop app you can talk to.* The incumbents proved shopkeepers will adopt a digital khata. We reach the shopkeepers they leave out, the ones who won't or can't type, and we make every user faster at the counter.

---

## 5. Social impact

### 5.1 Mapping to the FutureMakers challenge areas

| Challenge area | How the app contributes | Evidence it matters |
|---|---|---|
| **Digital access & education** *(primary)* | Speaking Bangla replaces typing, and the camera replaces searching lists. A shopkeeper with little schooling can still keep accurate digital books | 42.45% below fifth-grade literacy; functional literacy 62.92% |
| **Gender equality & inclusion** | Women running home-based or small shops get a record of their business without relying on a literate relative to keep books. That record can support a loan application | Women-led firms hold 7.28% of small-business loans against a 15% target |
| **Skills development & jobs** | Shopkeepers and their helpers learn digital bookkeeping, and a helper can record sales by voice. Profit and stock data help shops survive and keep employing people | 60%+ of micro-enterprises can't access credit |
| **Safety, security & data privacy** | Each shop's data is locked to that shop by the database; the AI can't save anything without the shopkeeper's confirmation; we have a compliance plan for the 2025 data law (§8) | PDPO 2025 obligations on consent and data handling |

**Sustainable Development Goals:** SDG 1 (No Poverty), SDG 5 (Gender Equality), SDG 8 (Decent Work & Economic Growth), SDG 9 (Industry & Innovation), SDG 10 (Reduced Inequalities).

### 5.2 Theory of change

```
INPUT            ACTIVITY                    OUTPUT                     OUTCOME                         IMPACT
Bangla voice  →  Shopkeeper records every →  Accurate stock, profit  →  Fewer stock-outs, baki      →  Higher, steadier shop
+ camera AI      sale by voice or camera      and baki ledger            collected, better buying       income; credit access;
app                                                                       decisions; a sales history     more women-run shops
                                                                          a lender can read               become financially visible
```

### 5.3 How we will measure impact

Promising impact isn't enough, so the pilot (§7) will measure it. These indicators come straight from data the app already records, plus a short survey at sign-up and after 3 months.

| Outcome | Indicator | Source |
|---|---|---|
| Inclusion | % of users who sell mainly by voice or camera; % women owners; % owners below fifth-grade schooling | Sign-up survey + app usage |
| Time saved | Seconds per checkout, before and after | Timed observation + app data |
| Baki recovered | ৳ of customer credit collected vs. outstanding, month by month | Khata ledger |
| Profit awareness | % of shops that check profit weekly; owners who can state their monthly profit | App usage + survey |
| Stock control | Number of times a top-selling item runs out | Inventory data |
| Financial access | Shops that use their app record for a loan or supplier credit | Partner data + survey |

### 5.4 Responsible AI

- **A person always confirms.** No AI output is saved without the shopkeeper approving it.
- **The AI can't invent products.** It can only pick from the shop's own list; anything else is thrown away by the server.
- **Mistakes fail safely.** If the AI is unsure, it asks rather than guesses. If the AI service is down, the shopkeeper sees an error and can sell manually, rather than seeing a wrong result.
- **Shop data stays private.** We use Google's paid AI service, where business data is not used to train Google's models (the free tier is for testing only).

---

## 6. Business model & financials

### 6.1 What it costs to run

There are three running costs: **AI (Gemini)**, **server (Supabase)** and **internet**.

**AI cost per voice or camera sale** (estimate, ৳)

The app currently sends the shop's **whole product list** to the AI with every request, so cost grows with shop size:

| Shop size | Voice sale | Camera scan, today's model (2026 price) | Camera scan, today's model (**from Jan 2027**, price doubles) | Camera scan on the cheaper model |
|---|---|---|---|---|
| 100 products | ৳0.27 | ৳0.38 | ৳0.76 | ৳0.19 |
| 300 products | ৳0.44 | ৳0.77 | ৳1.54 | ৳0.34 |
| 1,000 products | ৳1.06 | ৳2.13 | ৳4.25 | ৳0.89 |

*Assumptions: Google's published prices ([Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)): Flash-Lite (voice) $0.30 / $2.50 per million input / output tokens; 3.6 Flash (scan) $0.75 / $3.75, rising to $1.50 / $7.50 on 1 Jan 2027. About 21–24 tokens per product in the list, 32 tokens per second of audio ([Gemini docs](https://ai.google.dev/gemini-api/docs/tokens)), an ~8-second voice clip, and 300–400 output tokens.*

**The key fix: send a shortlist, not the whole shop.** If the app sends the AI only the ~60 most likely products (recent sellers plus a name match), and uses the cheaper Flash-Lite model for the camera too, **every AI sale costs about ৳0.20 whatever the shop's size.** This is a few days of engineering, and it's needed before charging (see §8).

| AI sales per month | Optimised (~৳0.20 each) | Today, 300-item shop | Today, 300-item shop, 2027 prices |
|---|---|---|---|
| 300 (10/day) | ৳59 | ৳182 | ৳297 |
| 600 (20/day) | ৳117 | ৳364 | ৳595 |
| 900 (30/day) | ৳176 | ৳546 | ৳892 |

**Server:** Supabase Pro costs **$25 ≈ ৳3,075 a month** and includes 2 million AI-function calls ([Supabase pricing guide](https://toolradar.com/blog/supabase-pricing-2026)). That's enough for thousands of shops, so it works out at **under ৳10 per shop**. The free plan is fine for the pilot.

**Internet:** the shopkeeper uses their own mobile data. One camera scan uploads about 50–70 KB and one voice sale about 100–300 KB, so 20 AI sales a day uses only **about 100–200 MB a month**. Manual sales use almost nothing.

### 6.2 Pricing

| Plan | Price | Includes | Who it's for |
|---|---|---|---|
| **Free** | ৳0 | Inventory, khata, cart, history, dashboard, manual and quick-tap selling, plus **30 AI sales a month** to try it | Every shop. Builds habit and trust |
| **Smart** | **৳299 / month**, paid by bKash/Nagad | **600 AI voice and camera sales a month** (20 a day), priority support | Busy shops that want speed |
| **AI top-up** | ৳40 per 100 extra AI sales | Prepaid, like a mobile recharge | Heavy users. Familiar pay-as-you-go model |
| **Sponsored** *(Phase 2)* | Paid by a partner | The Smart plan, free to the shop | Distributors, FMCG brands or lenders paying for their retailer network |

**Why ৳299:** that's about ৳10 a day, less than one cup of tea at the counter. Saving one forgotten baki payment of a few hundred taka covers the whole month.

### 6.3 Unit economics (one Smart shop, optimised AI)

| | ৳ / month |
|---|---|
| Price | 299 |
| AI cost (600 sales × ৳0.195) | −117 |
| Payment fee (assumed ~2%) | −6 |
| Server share | −10 |
| **Contribution per shop** | **≈ 166 (55%)** |

**Break-even:** fixed costs of about **৳25,000 a month** (server ৳3,075; one part-time field agent and marketing ৳20,000; tools ৳2,000) ÷ ৳166 = **about 150 paying shops.**

### 6.4 Three-year scenario (illustrative, not a forecast)

| | Year 1 | Year 2 | Year 3 |
|---|---|---|---|
| Paying shops, end of year | 200 | 2,000 | 10,000 |
| Revenue | ৳3.6 lakh | ৳39.5 lakh | ৳2.15 crore |
| Contribution (55%) | ৳2.0 lakh | ৳21.9 lakh | ৳1.19 crore |

*Assumes ৳299/month and an average of the shop count at the start and end of each year. This leaves out sponsored plans and lending referrals.*

### 6.5 Other revenue streams (Phase 2+)

1. **Lending referrals:** with the shopkeeper's consent, share their sales history with a bank or microfinance partner and earn a referral fee per loan. Hishabee's finance partnership with Prime Bank shows banks want this kind of data.
2. **Sponsored retailer networks:** an FMCG company or distributor pays for the Smart plan for its retailers. In return it gets anonymised, consented sell-through data and faster restock orders.
3. **Supplier ordering:** a low-stock item turns into a restock order to a wholesaler, and we take a small commission.

---

## 7. Go-to-market plan

| Phase | Timeline | Goal | Key actions |
|---|---|---|---|
| **0. Fix & pilot** | Months 0–3 | 30–50 shops, impact data | Build offline manual sales and the AI shortlist (§8); give the app free to shops near campus; measure the §5.3 indicators |
| **1. Launch** | Months 3–12 | 1,000 users, 200 paying | Launch the Smart plan; field demos at the counter (voice is best shown live); shop-to-shop referrals (one free month per referral) |
| **2. Partner** | Year 2 | 2,000 paying | Sponsored plans with a distributor or FMCG brand; lending partner; Bangla QR payment recording |
| **3. Scale** | Year 3 | 10,000 paying | AI insights; supplier ordering; expansion beyond grocery shops (pharmacies, hardware) |

### 7.1 Partnership ideas for Grameenphone

1. **"Dokan data pack":** GP bundles or zero-rates the app's data for shopkeepers, which removes the internet-cost worry.
2. **AI top-ups through GP recharge:** shopkeepers already understand prepaid recharge, so AI credit can work the same way.
3. **GP's retail network as the pilot channel:** GP reported **more than 350,000 points of sale** in 2017 ([Telenor CMD 2017](https://www.telenor.com/wp-content/uploads/2017/02/Telenor-CMD-2017-Grameenphone.pdf); current figure not found). Many of them are mudi dokans that already know GP.
4. **Alignment with GP's "AI & I" programme** to become an AI-native telco ([Daily Star](https://www.thedailystar.net/business/organisation-news/press-releases/news/grameenphone-launches-ai-i-programme-become-ai)).

---

## 8. Risks and how we handle them

| Risk | Impact | Mitigation |
|---|---|---|
| **Needs internet for every sale** | High. TallyKhata works offline, and a failed sale with a customer waiting loses trust | **Before the pilot:** let manual sales be saved offline and synced later, with AI used only when online |
| **AI cost grows with shop size** | High. A 1,000-item shop can cost ৳1–4 per AI sale | **Before charging:** send a ~60-product shortlist and use the cheaper model for camera scans (§6.1). Caps and prepaid top-ups protect the margin |
| **AI price rise on 1 Jan 2027** | Medium. Today's camera model doubles in price | Move camera scans to Flash-Lite, which has no scheduled increase |
| **Strong free competitors** | Medium | Compete on what they lack (voice and camera), and stay open to integrating with them |
| **AI misreads a sale** | Medium | Confirmation is required before saving; the AI can only pick from the shop's own products; stock is updated safely on the server |
| **Data protection law** | Medium | Clear Bangla consent at sign-up, a privacy policy, data-retention rules. **Our database currently runs in Tokyo.** We will review the law's cross-border and local-storage rules with a lawyer and move to the nearest compliant region if needed |
| **Adoption and trust** | Medium | Live demos at the counter, a free tier, referrals, and a Bangla-first design |
| **Team and ownership** | Medium | A written agreement among the three founders on ownership and roles before any revenue |

---

## 9. What we need

| Need | Use |
|---|---|
| **Mentorship** (FutureMakers development phase) | Pricing validation, pilot design, telco partnership |
| **~৳1.5 lakh pilot budget** | Server and AI for 50 shops for 3 months (under ৳20,000), field visits and printed Bangla guides, survey work |
| **Grameenphone partnership** | A data bundle and access to GP retailers for the pilot |

---

## 10. Conclusion

Bangladesh has millions of small shops and a ready-made push to go digital through the Bangla QR mandate. Existing tools mostly serve shopkeepers who are comfortable typing. **AI Shopkeeper Assistant brings proper bookkeeping (stock, profit, baki and a history a lender can read) to shopkeepers who would rather talk.** The core app is built and tested. AI costs about ৳0.20 per sale once the planned optimisation is done, and the business breaks even at about 150 paying shops. The next step is a 50-shop pilot that measures the impact rather than assuming it.

---

## Sources

**Competition**
- [Grameenphone launches second FutureMakers competition — The Daily Star](https://www.thedailystar.net/news/technology/news/grameenphone-launches-second-futuremakers-competition-4263831)
- [Grameenphone invites students to FutureMakers AI competition — TBS](https://www.tbsnews.net/economy/corporates/grameenphone-invites-students-futuremakers-ai-competition-1531251)
- [FutureMakers returns for its 2nd edition — Prothom Alo](https://en.prothomalo.com/corporate/a3g49dbrii)

**Market & connectivity**
- [Economic Census 2024 report — UNB](https://unb.com.bd/category/Bangladesh/economic-census-2024-report-released-economic-units-grew-nearly-50-in-a-decade/183102)
- [ShopUp secures $30m debt financing — Dhaka Tribune](https://www.dhakatribune.com/business/281651/shopup-secures-30m-debt-financing-to-fuel)
- [Overview of Bangladesh Retail Industry — Scribd](https://www.scribd.com/document/139715168/Bangladesh-retailing-industry)
- [Inventory Management Techniques for Grocery Shops in Bangladesh — ResearchGate](https://www.researchgate.net/publication/374000317_Inventory_Management_Techniques_for_Grocery_Shops_in_Bangladesh_A_Study_on_a_Grocery_Shop_in_Khulna_City)
- [Internet subscriber growth outpaces mobile connections — Financial Express](https://thefinancialexpress.com.bd/trade/internet-subscriber-growth-outpaces-mobile-connections-in-h1)
- [Mobile phone ownership rises: BBS — UNB](https://unb.com.bd/category/Bangladesh/mobile-phone-ownership-rises-bbs/195830)
- [BBS survey: household internet and smartphone access — Dhaka Tribune](https://www.dhakatribune.com/bangladesh/415972/bbs-survey-over-57%25-of-bangladeshi-households-now)
- [Bangla QR merchant figures — The Observer](https://observerbd.com/news/586785)
- [One QR, every wallet — The Daily Star](https://www.thedailystar.net/supplements/the-qr-era/news/one-qr-every-wallet-4232541)

**Social indicators**
- [42% below fifth-grade education — Bonik Barta](https://en.bonikbarta.com/bangladesh/c2Aj8lzZeMef4q32)
- [Functional literacy rate 62.92%: BBS — Prothom Alo](https://en.prothomalo.com/bangladesh/c7axno0vhh)
- [Gender disparity rising in SME finance — Dhaka Tribune](https://www.dhakatribune.com/business/banks/417380/gender-disparity-rising-in-sme-finance)
- [Digital lending for small businesses and merchants — TBS](https://www.tbsnews.net/thoughts/digital-lending-small-businesses-and-merchants-513798)

**Competitors**
- [Million shopkeepers using TallyKhata — TallyKhata](https://www.tallykhata.com/million-shopkeepers-using-tallykhata-app-for-records-and-payments/)
- [Hishabee](https://hishabee.io) · [Hishabee Impact Report 2025](https://www.hishabee.io/impact) · [Hishabee Inventory Finance](https://www.hishabee.io/finance)
- [Startup Bangladesh invests in Hishab](https://www.startupbangladesh.vc/startup-bangladesh-invests-in-hishab-telephony-driven-generative-ai/)
- [ShopUp debt financing — TBS](https://www.tbsnews.net/dropped/startups/shopup-secures-30m-debt-financing-boost-expansion-supply-chain-578646)

**Costs, law & Grameenphone**
- [Gemini API pricing — Google](https://ai.google.dev/gemini-api/docs/pricing)
- [Understand and count tokens — Google](https://ai.google.dev/gemini-api/docs/tokens)
- [Supabase pricing 2026 — Toolradar](https://toolradar.com/blog/supabase-pricing-2026)
- [Personal Data Protection Ordinance 2025: key takeaways — The Daily Star](https://www.thedailystar.net/tech-startup/news/bangladeshs-personal-data-protection-ordinance-2025-key-takeaways-4015401)
- [Key highlights of the PDPO 2025 for businesses — Mahbub & Company](https://mahbub-law.com/key-highlights-of-the-personal-data-protection-ordinance-2025-for-businesses)
- [Grameenphone launches "AI & I" programme — The Daily Star](https://www.thedailystar.net/business/organisation-news/press-releases/news/grameenphone-launches-ai-i-programme-become-ai)
- [Telenor Capital Markets Day 2017 — Grameenphone](https://www.telenor.com/wp-content/uploads/2017/02/Telenor-CMD-2017-Grameenphone.pdf)
- [Grameenphone digital solution collaborates with PriyoShop — TBS](https://www.tbsnews.net/node/1012286)
