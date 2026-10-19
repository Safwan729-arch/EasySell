# Remove "AI Insights" and "Trends" from Settings (2026-10-20)

Settings had an **Assistant** section with two entries, "AI Insights" and
"Trends". Both are removed, along with their screens, routes and strings.

## Why

- **They could never show anything.** They read the `insights` and
  `trend_data` tables, which Member B was to fill from Edge Functions. Those
  tables were never created (confirmed live in the 19 Oct review), so both
  screens always said "No insights yet" / "No trends yet".
- **The real AI advice lives elsewhere.** "Get advice from EasySell AI" on the
  Money health card (`money-tips`) is the shipped version of the same idea, and
  sales trends are on Home and Reports. Two empty screens next to it only
  confused judges and users.
- The owner asked for the removal before the hackathon submission.

## What went

- `lib/features/insights/` and `lib/features/trends/` (repository, model,
  screen each). Nothing else imported them.
- Routes `/insights` and `/trends` in `app_router.dart`.
- The Settings "Assistant" section.
- 12 strings from `app_en.arb` and `app_bn.arb` (removed line by line so the
  rest of each file kept its formatting), then `flutter gen-l10n`.

## Rejected

- **Hiding the entries behind a flag:** keeps dead code that reads tables that
  don't exist. If Member B ships insights later, a new screen should be built
  on what they actually deliver.

`CLAUDE.md` still describes `insights/` and `trends/` in its layout and in the
Member B contract; it was left unchanged because that file is the team's own
brief.
