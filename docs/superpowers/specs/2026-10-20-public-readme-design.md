# Public README for the hackathon (2026-10-20)

The repository went public for judging, so `README.md` was rewritten from the
Flutter boilerplate into the project's front page: pitch, APK download,
features, architecture, evidence, setup and roadmap.

## Decisions

- **"Interactive" means what GitHub renders, no scripts.** GitHub strips
  JavaScript from READMEs. The interactivity is `<details>` sections (one per
  feature, kept closed so the page stays short), anchor links in the top bar,
  Mermaid diagrams (architecture, a voice sale, the data model, a build
  timeline), LaTeX for the restock maths, GitHub alert boxes and task lists.
- **No demo password in the README.** A public repo is indexed and read by
  anyone. The README links the Drive folder, and the login lives only in that
  folder's read-me and in the evidence doc, so it isn't in search results or
  in git history for good.
- **Images live in `docs/readme/`**, made from the screenshots already used in
  the technical doc and deck. They are palette PNGs on transparent backgrounds,
  trimmed and at most 860 px wide (under 130 KB each), so they read in both
  GitHub themes and don't bloat the repo.
- **Every number is copied from the evidence pack or the code**, not from
  memory. The check caught two mistakes in the draft: the transaction types are
  `sale / restock / adjustment` (not "removal"), and the restock list turns red
  below 3 days left (`RestockItem.isUrgent`), not "within 2 days".
- **The Mermaid diagrams were test-rendered** with `@mermaid-js/mermaid-cli`
  11.4.2 driving the installed Chrome (`PUPPETEER_SKIP_DOWNLOAD=1` plus an
  `executablePath` config), because GitHub shows nothing useful when a diagram
  fails to parse.
- **No team names or licence.** Team details are still placeholders elsewhere,
  and choosing a licence is the owners' call.

## Later change (2026-10-20)

- **The "Try it" section was removed at the user's request**: the APK download
  link, install steps and "what to try first" list. Judges get the APK and the
  demo login through the hackathon submission (Drive folder, execution
  evidence), not the public README. The top-bar "Try it" link went with it, and
  the Android badge now points to "Run it yourself".
- **The closing "Built for the SME Finance Copilot track" line was removed**,
  also at the user's request. The "Honest limits" bullet that still listed a
  daily AI limit as missing was corrected (built in migrations 0023/0024); it
  now names backups instead, matching the security report.
