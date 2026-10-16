# AI Shopkeeper Assistant — Business Plan

**For:** GP FutureMakers 2026
**Date:** 13 October 2026
**Stage:** App built and tested. No paying customers yet.

> All prices are in Taka (৳) at **৳123 = US$1**. AI costs are estimates based on the app's code and Google's published prices.

---

## 1. Summary

| | |
|---|---|
| **What it is** | A shop app for Bangladesh's small grocery shops. The shopkeeper makes a sale by **speaking Bangla** or **pointing the camera**, and the app keeps stock, profit and customer credit (baki) up to date |
| **Who pays** | Busy shops that want faster, easier selling |
| **Price** | Free basic app. **Smart plan: ৳299 a month** (about ৳10 a day) |
| **Cost to serve one paying shop** | About **৳133 a month** |
| **Money left per shop** | About **৳166 a month (55%)** |
| **Break-even** | About **150 paying shops** |
| **Year 3 target** | 10,000 paying shops, **৳2.15 crore revenue**, about **৳83.5 lakh profit** |
| **Funding needed** | About **৳2.5 lakh** to cover the pilot and the first year |

---

## 2. The opportunity

**How many shops could use it?**

| | Number | Source |
|---|---|---|
| Small shops in Bangladesh | **1–4.5 million** (estimates vary) | [Industry overview](https://www.scribd.com/document/139715168/Bangladesh-retailing-industry); [ShopUp via Dhaka Tribune](https://www.dhakatribune.com/business/281651/shopup-secures-30m-debt-financing-to-fuel) |
| Shops whose owner has a smartphone | **About 2–3 million** | 73.4% of households own a smartphone ([BBS via Dhaka Tribune](https://www.dhakatribune.com/bangladesh/415972/bbs-survey-over-57%25-of-bangladeshi-households-now)) |
| Our 3-year target | **10,000 paying shops** | Less than 0.5% of these shops |

**Why now?**
- **Shops must go digital.** Bangla QR payments became compulsory for all merchants on 1 July 2026, and 2.4 million merchants had signed up by August ([The Observer](https://observerbd.com/news/586785)).
- **AI is now cheap.** One AI-recorded sale costs about **৳0.20** once the app is optimised (see §4).
- **Typing is a barrier.** 42% of people are below fifth-grade literacy ([Bonik Barta](https://en.bonikbarta.com/bangladesh/c2Aj8lzZeMef4q32)). A voice-first app reaches shopkeepers that typing apps miss.

---

## 3. What we sell

**Free plan.** Stock list, sales, customer credit book, sales history, daily profit, and 30 AI sales a month to try voice and camera.

**Smart plan (৳299 a month).** Includes 600 AI voice or camera sales a month (20 a day). Paid by bKash or Nagad.

**AI top-up.** ৳40 for 100 extra AI sales, prepaid like a mobile recharge.

**Why shops will pay:** voice and camera make checkout faster, and the app shows real profit and who owes money. Collecting one forgotten ৳300 baki payment pays for the whole month.

---

## 4. Costs

The app has three running costs.

### 4.1 AI cost per sale

Each voice or camera sale is one call to Google's Gemini AI. **Right now the app sends the shop's whole product list with every call, so bigger shops cost more:**

| Shop size | Voice sale | Camera sale (now) | Camera sale (from Jan 2027) |
|---|---|---|---|
| 100 products | ৳0.27 | ৳0.38 | ৳0.76 |
| 300 products | ৳0.44 | ৳0.77 | ৳1.54 |
| 1,000 products | ৳1.06 | ৳2.13 | ৳4.25 |

*Based on Google's prices ([Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)). The camera's AI model doubles in price on 1 January 2027.*

**The fix (a few days of work):** send only the ~60 most likely products, and use Google's cheaper AI model for the camera too. Then **every AI sale costs about ৳0.20, whatever the shop size.**

This fix decides whether the business works:

| Smart plan shop (600 AI sales a month) | AI cost | Money left from ৳299 |
|---|---|---|
| **With the fix** | ৳117 | **+৳166 profit** |
| Without the fix, 300-item shop, now | ৳364 | **−৳81 loss** |
| Without the fix, 300-item shop, 2027 | ৳595 | **−৳312 loss** |

### 4.2 Server and internet

- **Server (Supabase):** **৳3,075 a month** (US$25) covers thousands of shops, so it's under ৳10 per shop ([pricing guide](https://toolradar.com/blog/supabase-pricing-2026)). The pilot can use the free plan.
- **Internet:** the shopkeeper uses their own phone data. 20 AI sales a day uses only about 100–200 MB a month.

---

## 5. Money per paying shop

| | ৳ a month |
|---|---|
| Smart plan price | 299 |
| AI cost (600 sales at ৳0.195) | −117 |
| Payment fee (about 2%) | −6 |
| Server share | −10 |
| **Money left per shop** | **166 (55%)** |

---

## 6. Break-even

**Monthly fixed costs: about ৳25,000.** That's the server (৳3,075), one part-time field agent plus marketing (৳20,000) and software tools (৳2,000). The founders are unpaid in year 1.

**Break-even = fixed costs ÷ money left per shop.**

| Price | Money left per shop | Shops needed to break even |
|---|---|---|
| ৳199 | ৳68 | 368 |
| **৳299** | **৳166** | **151** |
| ৳399 | ৳264 | 95 |

We chose ৳299. It's affordable (about ৳10 a day) and needs only about 150 shops to cover costs.

---

## 7. Three-year forecast

| | Year 1 | Year 2 | Year 3 |
|---|---|---|---|
| Paying shops (end of year) | 200 | 2,000 | 10,000 |
| Revenue | ৳3.6 lakh | ৳39.5 lakh | ৳2.15 crore |
| Money left after per-shop costs | ৳2.0 lakh | ৳21.9 lakh | ৳1.2 crore |
| Fixed costs (team, marketing, server) | ৳3.0 lakh | ৳7.2 lakh | ৳36 lakh |
| **Profit / (loss)** | **(৳1.0 lakh)** | **৳14.7 lakh** | **৳83.5 lakh** |

*Assumptions: ৳299 a month; shop numbers grow evenly through each year; fixed costs rise to ৳60,000 a month in year 2 and ৳3 lakh a month in year 3 (a team of about 8). These are plans, not guarantees.*

---

## 8. Extra income (year 2 onwards)

1. **Sponsored shops.** A distributor or brand pays the Smart plan for the shops it supplies, in return for anonymous sales trends.
2. **Loan referrals.** With the shopkeeper's permission, we share their sales record with a bank and earn a fee for each loan. Hishabee already does this with Prime Bank ([Hishabee](https://www.hishabee.io/finance)).
3. **Supplier orders.** When stock runs low, the app places a restock order with a wholesaler, and we take a small commission.

None of this is counted in the forecast above.

---

## 9. How we get customers

| Phase | When | Goal | How |
|---|---|---|---|
| **Pilot** | Months 0–3 | 50 shops using it free | Fix offline sales and AI cost first; sign up shops near campus; measure results |
| **Launch** | Months 3–12 | 200 paying shops | Show voice selling live at the counter; give a free month for each shop referred |
| **Grow** | Year 2+ | 2,000 → 10,000 | Partner with distributors and banks; ask Grameenphone for a shop data pack |

**Grameenphone partnership ideas:** a "Dokan data pack" for shopkeepers, selling AI top-ups through GP recharge, and using GP's retailer network for the pilot.

---

## 10. Competitors

| | What they offer | Our difference |
|---|---|---|
| **TallyKhata** | Free credit book and payments, 1 crore+ downloads, works offline ([TallyKhata](https://www.tallykhata.com/million-shopkeepers-using-tallykhata-app-for-records-and-payments/)) | They need typing. We sell by **voice and camera** |
| **Hishabee** | Shop software plus stock loans up to ৳50,000 ([Hishabee](https://hishabee.io)) | Typing-based. We could partner rather than compete |
| **Paper khata** | Free and familiar | No totals, no profit, no history |

---

## 11. Risks

| Risk | What we do |
|---|---|
| **AI cost too high** | Make the AI-cost fix (§4.1) before charging anyone. Monthly AI limits plus prepaid top-ups mean no shop can cost more than it pays |
| **Every sale needs internet** (TallyKhata works offline) | Let normal sales save offline and sync later. Use AI only when online |
| **Shops won't pay** | Free plan first, then paid. A ৳199 plan still breaks even at 368 shops |
| **AI gets a sale wrong** | The shopkeeper confirms every AI sale before it's saved |
| **Data protection law (2025)** | Clear consent, a privacy policy, and a legal check on where data is stored (currently Tokyo) |

---

## 12. What we need

| Item | Amount |
|---|---|
| Pilot (50 shops, 3 months: AI, travel, printed guides) | ৳1.5 lakh |
| Year 1 loss (from §7) | ৳1.0 lakh |
| **Total** | **About ৳2.5 lakh** |

We'd also value mentorship on pricing, and a partnership with Grameenphone for data packs and pilot shops.

---

## 13. Social impact (short)

- **Includes people who can't type:** voice and camera selling in Bangla.
- **Helps shops earn more:** they see real profit, keep stock and collect baki.
- **Opens access to loans:** a digital sales record can support a loan application. This matters most for women, whose businesses get only 7.28% of small-business loans against a 15% target ([Dhaka Tribune](https://www.dhakatribune.com/business/banks/417380/gender-disparity-rising-in-sme-finance)).

---

## Sources

- [Bangladesh retailing industry overview — Scribd](https://www.scribd.com/document/139715168/Bangladesh-retailing-industry)
- [ShopUp secures $30m debt financing — Dhaka Tribune](https://www.dhakatribune.com/business/281651/shopup-secures-30m-debt-financing-to-fuel)
- [BBS: household internet and smartphone access — Dhaka Tribune](https://www.dhakatribune.com/bangladesh/415972/bbs-survey-over-57%25-of-bangladeshi-households-now)
- [Bangla QR merchant figures — The Observer](https://observerbd.com/news/586785)
- [42% below fifth-grade education — Bonik Barta](https://en.bonikbarta.com/bangladesh/c2Aj8lzZeMef4q32)
- [Gemini API pricing — Google](https://ai.google.dev/gemini-api/docs/pricing)
- [Supabase pricing 2026 — Toolradar](https://toolradar.com/blog/supabase-pricing-2026)
- [Million shopkeepers using TallyKhata — TallyKhata](https://www.tallykhata.com/million-shopkeepers-using-tallykhata-app-for-records-and-payments/)
- [Hishabee](https://hishabee.io) · [Hishabee Inventory Finance](https://www.hishabee.io/finance)
- [Gender disparity rising in SME finance — Dhaka Tribune](https://www.dhakatribune.com/business/banks/417380/gender-disparity-rising-in-sme-finance)
