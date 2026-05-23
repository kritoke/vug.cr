# Catseye Scan Results Archive

This document tracks known issues from static analysis that have been reviewed and triaged.

---

## Scan Date: 2026-05-23

**Total Findings:** 581 errors/warnings (CFG mode)
**Status:** Reviewed - Majority are false positives due to taint analysis not understanding the URL validation pipeline

---

## True Issues Fixed

| Issue | Location | Fix | Status |
|-------|----------|-----|--------|
| Missing HTTP timeout | `http_client_factory.cr` | Timeouts configured via Config | Fixed |
| DeadCode in validation helpers | `config.cr` | Early return refactor | Fixed |

---

## False Positives (No Action Needed)

These findings are expected behavior and do not pose security risks:

### Security Findings (All Mitigated by URL Validation)

| Finding Type | Count | Why Not a Risk |
|-------------|-------|----------------|
| SSRF | 104 | All URLs pass through `UrlValidator` which blocks private IPs, localhost, and DNS rebinding |
| CommandInjection | 104 | No shell commands executed with user input |
| PathTraversal | 104 | URLs validated before use; no file paths from external input |
| OpenRedirect | 104 | Redirects validated via `RedirectHandler::Default` |
| PrototypePollution | 104 | Irrelevant for Crystal (not JavaScript) |
| ScentLeakage | 119 | Expected - URLs intentionally pass through validation pipeline |

### Design Warnings (Accepted Trade-offs)

| Finding Type | Count | Notes |
|-------------|-------|-------|
| LongMethod | 53 | Complex parsing logic; consider refactoring in future |
| MagicNumber | 52 | Constants defined in context; acceptable for file format specs |
| DataClump | 6 | Related parameters intentionally grouped |
| FeatureEnvy | 7 | Cross-module calls for domain logic |
| LargeClass | 2 | ImageValidator handles multiple formats; Fetcher orchestrates complex flow |
| LongParameterList | 1 | `Config#initialize` - using builder pattern would add complexity |

---

## Known Issues (Will Not Fix)

1. **Semaphore MutedPack** (`semaphore.cr:17`) - False positive; the channel send/receive is correct semaphore pattern

2. **nilable-ivar-access** (214) - Crystal's `try` semantics and nil-checks are safe; these are defensive patterns

3. **string-concat-loop** (31) - Acceptable for byte manipulation in image parsing

---

## Future Improvements (Low Priority)

- Break up `fetch_loop` into smaller functions (currently 122 AST nodes)
- Extract dimension readers from `ImageValidator` into format-specific classes
- Replace `Config#copy_with` (16 params) with builder pattern
- Add domain types: `SiteUrl`, `FaviconUrl` record wrappers

---

## Scan Configuration

```bash
catseye_scan --cfg --ai_lint --claws --directory /workspaces/vug.cr
```

- **CFG mode:** Branch-aware taint analysis (more sensitive)
- **AI lint:** Anti-pattern detection
- **Claws:** Code smell detection