# Completed Improvements

A record of all completed technical improvements and fixes.

---

## 2026-05-23

### CI-001: Logo Filtering for Favicons

**Date Completed:** 2026-05-23  
**Commit:** a45bc5e

**Changes:**
- Added `LOGO_INDICATORS` constant with terms: `logo`, `channel`, `brand`, `header`, `banner`, `profile`, `avatar`, `artwork`
- Modified `FaviconCollection#best` to filter URLs containing logo-related terms
- Deprioritized images larger than 128x128 pixels (likely logos)
- Added comprehensive tests covering all indicator terms and real-world scenarios
- Added mock tests for arstechnica, YouTube, and Twitch-style URL patterns

**Files Modified:**
- `src/vug/favicon_collection.cr`
- `spec/vug/favicon_collection_spec.cr`

**Testing:**
- 24 new tests added
- All 282 tests passing

---

### CI-002: Validation Helper Refactor

**Date Completed:** 2026-05-23  
**Commit:** f41640d

**Changes:**
- Simplified `validate_positive_timespan` with early return
- Simplified `validate_positive_int` with early return
- Simplified `validate_non_negative_int` with early return
- Removed unreachable code after unconditional return/raise
- Added documentation comments to `Semaphore` class

**Files Modified:**
- `src/vug/config.cr`
- `src/vug/semaphore.cr`
- `src/vug/url_validator.cr`
- `src/vug/fetcher.cr`
- `src/vug/html_extractor.cr`
- `src/vug/data_url_handler.cr`
- `src/vug/manifest_extractor.cr`

---

### CI-003: HTTP Client Timeouts (Pre-existing)

**Status:** Already implemented in current codebase

**Details:**
- `http_client_factory.cr` properly configures all timeout types
- `read_timeout`: 30 seconds default (configurable)
- `connect_timeout`: 10 seconds default (configurable)
- `write_timeout`: 10 seconds default (configurable)

**File:** `src/vug/http_client_factory.cr`

---

### CI-004: Catseye False Positive Documentation

**Date Completed:** 2026-05-23

**Documents Created:**
- `docs/archive/catseye-scan-2026-05-23.md` - Full scan results
- `todo.md` (moved to `planning/roadmap.md`) - False positive reference
- `docs/archive/completed-improvements.md` - This file

---

## Metrics At Time of Review

| Metric | Before | After |
|--------|--------|-------|
| MissingTimeout | 1 | 0 ✅ |
| DeadCode (unreachable) | 3 | 0 ✅ |
| LongMethod (critical) | 53 | 53 (in progress) |
| Logo filtering | No | Yes ✅ |

---

*Last Updated: 2026-05-23*