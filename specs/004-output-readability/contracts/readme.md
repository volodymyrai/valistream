# Contract: README.md (004)

**Scope**: the repository `README.md` rewritten as a GitHub onboarding guide. Every claim must be verified
against the released `0.4.0` behavior before completion (FR-037, SC-010).

## 1. Structure (FR-029)

README contains, in a recognizable GitHub order:
project name + concise description · motivation/problem · key capabilities · how it works · quick start ·
installation · usage · option reference · output modes · generated artifacts · realistic examples ·
exit codes · troubleshooting · limitations/platform support · links to project resources.

## 2. Badges (FR-029a, SC-010)

- B1. A minimal badge set near the top, each backed by a verifiable fact: **license**, **latest
  release/version** (`0.4.0`), **platform/Swift version**, **code coverage**.
- B2. Every displayed badge reflects a real, current value. A badge whose fact cannot be verified is
  **omitted**, never shown stale or broken.
- B3. The coverage badge value comes from the `Valistream/TestPlans/Valistream.xctestplan` coverage run
  (`codeCoverage` enabled for `Valistream` + `ValistreamCore`), measured via `xcrun xccov` against the
  result bundle (research D15). The report-level badge prohibition (report-format R16 / FR-027a) does not
  apply to the README.

## 3. Installation (FR-030)

- I1. **Primary verified method**: download the prebuilt `valistream-cli.zip` from a GitHub Release
  (published alongside the auto-generated source archive) and run it.
- I2. **Secondary verified method**: source build with stated prerequisites and steps.
- I3. Unpublished channels (Homebrew or other package managers) are explicitly marked **unsupported**, not
  presented as available. Supported platforms and prerequisites are stated explicitly; unsupported
  platforms are identified.

## 4. Quick start (FR-031/035/037)

- Q1. Takes a user from installation to a first validation and explains where the resulting report and
  evidence are written.
- Q2. The copy-paste command uses a **stable, credential-free public HLS test stream** that runs as-is on
  paste; it is confirmed to resolve and run cleanly with `0.4.0` before inclusion (no dead link, no
  misleading error). Generic syntax elsewhere may use a placeholder URL.
- Q3. Explains the end-to-end workflow: stream discovery → selection → validation → live monitoring →
  evidence capture → report generation, in user-oriented language.

## 5. Options & output modes (FR-032/036)

- O1. Parameter docs match `0.4.0` `--help`: defaults, accepted value forms, mutually exclusive options,
  non-interactive behavior, and omission of hidden options.
- O2. Output-mode guidance states which mode suits interactive monitoring, automation, concise review, and
  diagnosis.

## 6. Examples (FR-033/034)

- E1. Plain-text fenced excerpts only — **no** screenshots, GIFs, or terminal casts (GitHub renders no ANSI
  in code blocks; plain text is the baseline).
- E2. Representative excerpts for: quiet, normal, verbose, no-color/redirected, structured-stream, Markdown
  report, and session-directory layout.
- E3. All inputs/outputs sanitized and stable; no credentials, tokens, private addresses, or expiring
  signed URLs.

## 7. Exit codes & version

- X1. Documents exit codes 0/1/2/3/130 exactly as the frozen contract.
- X2. All version strings read `0.4.0` and agree with `--version` and help.

## 8. Acceptance inputs (FR-038)

- A1. The user's conversation-only live ("TV Nord") and VOD ("NRK news") streams are used for realistic
  manual acceptance of terminal readability and README examples; their URLs stay **out of committed
  artifacts** unless the user explicitly confirms they are public and suitable for publication.
