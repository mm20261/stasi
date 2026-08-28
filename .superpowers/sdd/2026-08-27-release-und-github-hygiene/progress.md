# SDD ledger — plan: docs/superpowers/plans/2026-08-27-release-und-github-hygiene.md

Baseline entering plan: commit 7dd185a; 506 tests, 4 skipped, 0 failures; debug/release green.
Spec: docs/superpowers/specs/2026-08-27-stabilisierung-und-github-release-design.md

## Carried Task 0

Residual findings from Hotkey/Sound final scoped review:

- RuntimeErrorReporter synchronous acceptance currently performs NSLock/AsyncStream work on AUHAL RT callback. Need RT-safe atomic acceptance plus off-RT delivery, while stop awaits delivery flush before commit.
- PID-targeted TextInjector must abort entire chunk sequence on event construction failure, never continue with mangled text.
- First-start empty-state copy still promises immediate speaking; must say wait for start tone.
- Onboarding Escape must not leave a dead-end empty draft/removed monitor; return to saved valid combo/non-capturing state or provide direct retry.

Ruling: RuntimeErrorReporter uses only atomic/constant-time acceptance on RT. Session health/ingress close happens on worker/delivery context. `AudioCapture.stop()` awaits accepted-delivery flush after processing drain and before clearing callback/returning URL. If wrong, either RT blocks or commit misses terminal error.

Ruling: TextInjector routing returns success/failure and aborts the whole remaining chunk sequence on first failed down/up creation. AppState treats injection failure as no successful injection and keeps clipboard/history truth.

Ruling: Onboarding Escape exits capture and restores the saved combo as explicit cancellation result, leaving Continue usable; no hidden active monitor.

## Preflight scan

### Task self-consistency

| Task | Tests against implementation | Files/interfaces | Finding |
|---|---|---|---|
| 0 | RT delivery flush, injection abort, copy, onboarding escape | Must land before release verification | Consistent |
| 1 | Smoke-test first red on missing SwiftPM bundle; clean-room launch | `make-app.sh` + new smoke script | Consistent; script must not hang or touch real global tap |
| 2 | Smoke test extends license checks | Depends on Task 1 bundle copy | Consistent |
| 3 | Update state tests and UI mapping | `make-app.sh` Info.plist config | Consistent; no live GitHub dependency in tests |
| 4 | Grep-based documentation hygiene | README/AGENTS only | Consistent |
| 5 | Canonical icon + smoke test | Depends on Task 1 smoke and modifies make-app | Consistent; inspect before delete, preserve runtime menu icons |
| 6 | Local signing and docs | Depends on stable make-app | Consistent; no real notarization |
| 7 | Manual workflow validation | Depends on Tasks 1/2/6 docs/scripts | Consistent; no tag/push/release/upload |
| 8 | Full verification/hygiene | Verifies Tasks 0–7 | Consistent |
| 9 | History rewrite guide only | No mutation | Consistent |

### Shared files and interfaces

| Tasks | Shared surface | Handoff/finding |
|---|---|---|
| 0 → 8 | runtime/tests/docs | Final verification must include carried fixes |
| 1 → 2 | smoke script/resource bundle | License checks use exact SwiftPM resource paths established by Task 1 |
| 1 → 3/5/6 | `make-app.sh` | Preserve resource bundle while adding release URL, icon generation, signing modes |
| 1/2/5/6 → 7 | build/release scripts | CI invokes the final stable smoke/build/sign flow |
| 3 → 8 | update endpoint greps | Old URL must have no production/document hits |
| 4/5 → 8 | repo hygiene | No tracked derivatives, private hardware or architecture path |
| 6/7 → 8 | signing workflow | Local ad-hoc verified; CI only prepared |
| 8 → 9 | verified branch | History guide documents prerequisites but does not execute them |

Ruling: `scripts/smoke-test-app.sh` must have bounded waits and trap cleanup. It may kill only the PID it starts and must not move/delete the developer's real `.build`; use isolated output/copy to prove no absolute fallback. If wrong, smoke test can hang or damage local build state.

Ruling: One canonical existing 1024px icon is preserved byte-for-byte as `Resources/AppIcon.png`. Generated iconset/ICNS derivatives are removed only after smoke passes. Historical design handoff may be removed only after repository search proves no runtime/docs dependency. Git history makes deletion reversible.

Ruling: GitHub Actions runner availability is verified against current official GitHub documentation before choosing label. If macOS 26 public runner is unavailable, use documented current macOS runner and explain macOS 26 build requirement/self-hosted limitation; never commit a knowingly invalid label.
Ruling: External marketplace actions were not explicitly approved and the harness denied `actions/checkout`. Workflow uses only built-in shell/git to fetch the exact `$GITHUB_SHA` from `$GITHUB_REPOSITORY` with the scoped `GITHUB_TOKEN`, never mutable third-party action code. If wrong, manual checkout can leak token or fetch wrong ref; tests/greps must verify quoting, no xtrace, exact SHA checkout and credential cleanup.

Ruling: History rewrite operation is not executed. Exact replacement identity remains a future user decision; no mailmap with invented value, no filter-repo, no force push.
Ruling: Release credentials live only as secrets of protected GitHub Environment `release`, with required reviewers and deployment branch restricted to `main`. Secretless verify job can run any manual ref; credential job runs only trusted main after approval and fresh checkout. If wrong, collaborator-controlled branch code can exfiltrate signing identity.

Task 0: complete (commits 7dd185a..3462d68, review clean; 511 tests, debug/release green)
Task 1: fix round 1/5 (0 addressed, 5 open — Bundle.module root path wrong; smoke masked by .build fallback; real HOME used; unbounded wait; shared log; commits 3462d68..380c86b)
Task 1: Ruling: Smoke uses non-destructive sandbox denial of repo `.build` to prove no compiled absolute fallback. It never renames/deletes/chmods developer build state. If sandbox proof unavailable, task remains blocked rather than claim clean-room success.
Task 1: Ruling: Generated Bundle.module root expectation conflicts with standard macOS codesigning, which rejects root siblings next to Contents. Preserve signable `Contents/Resources/Stasi_Stasi.bundle`; introduce `StasiResources.bundle` that resolves packaged Bundle.main resource first and Bundle.module only for SwiftPM dev/test. All production resource callsites use resolver. If wrong, app is either unsigned/unsealable or relies on local .build fallback.
Task 1: fix round 1/5 (5 addressed, 0 open — resolver/layout, sandbox fallback denial, temp profile, bounded shutdown, per-run log; commits 380c86b..043a336)
Task 1: minor (deferred): sandbox policy denies real-home writes but smoke does not actively probe a harmless real-home write denial.
Task 1: complete (commits 3462d68..043a336, review clean; 1 minor deferred)
Task 2: complete (commits 043a336..c3d1fe6, review clean)
Task 3: complete (commits c3d1fe6..c70c429, review clean)
Task 4: fix round 1/5 (1 addressed, 0 open — portable SwiftPM-Testpfad präzise beschrieben; commits 7690227..924a8ac)
Task 4: complete (commits c70c429..924a8ac, review clean)
Task 5: complete (commit e09a395; canonical AppIcon.png SHA-256 9645bf86703d9b8272d54b3deb37bd2800bf8d3717819b230c5f51d031013889; 24 generated derivatives / 2,088,146 bytes removed; smoke + 516 tests green)
Task 5: minor (deferred): `make-app.sh` removes temporary iconset only after successful iconutil; failed sips/iconutil leaves ignored residue until next run. Final review should add failure-safe trap cleanup.
Task 6: complete (commits e09a395..e63d0e7, review clean)
Task 7: fix round 1/5 (1 addressed, 0 open — protected release environment/main trusted-ref credential boundary; commits e8aa43a..c7a62fa)
Task 7: complete (commits e63d0e7..c7a62fa, review clean; GitHub admin configuration mandatory)
Task 8: fix round 1/5 (0 addressed, 1 open — exact unfiltered hygiene greps still hit historical docs/superpowers literals; no commit in initial verification)
Task 8: Ruling: Public tracked historical plan docs are sanitized to remove obsolete architecture-path and dead-endpoint literals while preserving meaning. Exact unfiltered repo greps are the authority. If wrong, final hygiene claims contradict the committed tree.
Task 8: fix round 1/5 (1 addressed, 0 open — exact unfiltered hygiene greps and email evidence now clean; commits c7a62fa..4fbb3b3)
Task 8: complete (verification + docs hygiene review clean)
Task 9: fix round 1/5 (4 addressed, 0 open — commit-ID scope, mirror/ref coverage, filter-repo refs, tag/signature semantics; commits f3ac8c8..ac4d7ae)
Task 9: complete (commits 4fbb3b3..ac4d7ae, review clean; no history mutation)
Final fix wave: 8 important + 3 minor findings addressed test-first where product behavior changed. Strict SemVer/HTTPS/source-bound persistence, endpoint-link validation, scalar-safe injection, shared target gate for insertLast, history message/signature boundaries, failure-safe icon cleanup, harmless real-HOME sandbox denial probe, and historical checkout-plan correction landed without external action.
Final fix verification: 533 tests, 4 skipped, 0 failures; debug/release builds green; packaged app clean-room smoke and strict codesign green; workflow YAML/embedded Bash/security/hygiene checks green; no push, publish, release, notarization, or history rewrite.
