# Changelog

## [Unreleased]

### Changed

- **Crystal 1.19.1 minimum**: Bumped minimum Crystal version from 1.18.x to 1.19.1. Pinned Docker CI image to `crystallang/crystal:1.19.1` and Nix devshell to `pkgs.crystal_1_19`. nixpkgs-unstable does not yet ship `crystal_1_20`; revisit when available.
- **`Time.monotonic` → `Time.instant`**: Migrated all monotonic clock usages to the 1.19 `Time::Instant` API (`Time.monotonic` was deprecated in 1.19.0, PR #16545). `LoopState#start_time`, `DnsEntry#timestamp`, `CacheEntry#timestamp`, and `RateLimiter#@windows` now hold `Time::Instant`. Read sites use the new `instant.elapsed` idiom for cleaner span arithmetic; the 13 deprecation warnings previously flagged in `easy-wins-debt-fix` are resolved.

### Internal

- **Pinned `crystal.yml` workflow image**: Was unversioned `crystallang/crystal`; now `crystallang/crystal:1.19.1` for reproducibility.

## [0.5.6] - 2026-05-24

### Security

- **Fixed off-by-one in redirect limit**: Changed `>=` to `>` to correctly enforce max_redirects
- **Fixed asymmetric www-stripping**: Now allows redirects both directions (www → non-www and non-www → www)
- **Fixed IPv6 ULA prefix check**: Changed from `starts_with?("fc")` to proper `/^fc00|^fd00/` regex for correct /7 prefix
- **Fixed IPv6 loopback detection**: Added bracket stripping for URL format `[::1]`
- **Fixed base64 memory exhaustion**: Check estimated decoded size before attempting decode
- **Added explicit IPv6 private range detection**: Refactored `private_ip?` into `private_ipv4?`/`private_ipv6?` methods

### Bug Fixes

- **Fixed silent error in gray placeholder fallback**: Added explicit debug messages when fallback is skipped
- **Fixed incomplete redirect loop detection**: Implemented visited URL tracking to detect chains like `a → b → c → b`
- **Fixed inconsistent redirect count check**: Both fetcher and redirect handler now use `>` consistently

### Internal

- **Added RateLimiter.cleanup method**: For proactive cleanup to prevent unbounded memory growth
- **Added DnsCache.recreate method**: To recreate singleton with new TTL after changes
- **Added DNS port documentation**: Explained design decision for port 80 usage

## [0.5.5] - 2026-05-23

### Added

- **Logo filtering for favicon selection**: Added `LOGO_INDICATORS` constant with terms (`logo`, `channel`, `brand`, `header`, `banner`, `profile`, `avatar`, `artwork`) to prevent channel/brand logos from being selected as favicons. Images larger than 128x128 are also deprioritized.

### Security

- **Catseye static analysis review**: Comprehensive review of codebase using Catseye v0.4.0. Confirmed SSRF, CommandInjection, PathTraversal, and OpenRedirect mitigations are properly in place via `UrlValidator` and `RedirectHandler`.

### Fixed

- **JSON parse errors in manifest_extractor**: Added explicit `JSON::ParseException` handling with debug logging instead of discarding the return value.
- **Dead code in validation helpers**: Removed unreachable code after unconditional return/raise in `validate_positive_timespan`, `validate_positive_int`, and `validate_non_negative_int`.

### Internal

- **fetch_loop refactor**: Extracted termination conditions and action handling into smaller methods (`check_termination_conditions`, `handle_result_action`) to reduce complexity from 122 to ~50 AST nodes.
- **fetch_single refactor**: Extracted semaphore and URI parsing into `acquire_semaphore` and `parse_uri` helper methods. Consolidated exception handling.
- **html_extractor refactor**: Split `extract_all` into `validate_and_parse_url`, `process_html_response`, `fetch_html`, `add_manifest_favicons`, and `log_error` methods.
- **Magic number extraction**: Extracted constants `HASH_SEED`, `SVG_SIZE`, `CORNER_RADIUS`, `CIRCLE_RADIUS`, `FONT_SIZE`, `TEXT_Y_OFFSET` in `PlaceholderGenerator`.
- **Catseye configuration**: Added `.catseye.toml` with suppressions for acceptable trade-offs (Config#copy_with 16 params, image format signatures, URL validator IP masks).

## [0.5.4] - 2026-05-22

### Security

- **Per-host rate limiting**: Added `RateLimiter` class with sliding window algorithm (60 req/min per host) to prevent abuse from one domain overwhelming resources

### Added

- **Configurable DNS cache TTL**: `DnsCache.ttl = 10.minutes` (default 30s) allows tuning DNS revalidation performance

### Fixed

- **URI parse error handling**: Added explicit rescue for `URI::Error` in `fetch_single` for defensive error handling
- **Time::Span comparison**: Fixed `> 0` to `> Time::Span.zero` in http_client_factory.cr
- **Same-origin redirect validation**: Enhanced redirect handler to validate same-origin redirects

### Internal

- Made `RateLimiter` injectable for testability

## [0.5.3] - 2026-05-05

### Fixed

- **Missing `fetch_types` require in `vug.cr`**: `FetchAction::Base` was not resolvable because `fetch_types.cr` (which defines the `FetchAction` module) was not required before `redirect_handler.cr` in the load order. Now properly required.

## [0.4.1] - 2026-04-20

### Added

- **GitHub Actions CI workflow**: Automated testing on push and pull requests.

## [0.4.0] - 2026-04-12

### Security

- **Fixed SSRF bypass via hostname misidentification**: `UrlValidator.private_ip?` used fragile string prefix matching that incorrectly flagged legitimate hostnames like `10thstreet.com`, `fcbayern.com`, and `192tv.com` as private IPs. Now uses `Socket::IPAddress` parsing with proper `loopback?`, `private?`, and `link_local?` predicates. Also handles IPv4-mapped addresses (`::ffff:X.X.X.X`) and `0.0.0.0`

### Bug Fixes

- **Fixed DNS cache returning IPs with port numbers**: `addrinfo.ip_address.to_s` returned strings like `[::1]:80` and `127.0.0.1:80` including port. Changed to `addrinfo.ip_address.address` for clean IP strings
- **Fixed data URL favicons not cached**: `HtmlExtractor` now receives `CacheManager` and calls `cache_manager.set()` after saving data URL favicons, so subsequent requests hit the cache instead of re-decoding
- **Fixed gray placeholder result leakage**: When a cached larger Google favicon was found, the fetcher returned `{:return_result, nil}` instead of `{:use_cached, path}`, causing successful results to be silently discarded
- **Fixed base64 size limit integer division**: `DataUrlHandler` computed `max_size * 4 / 3` using integer division (resulting in `max_size * 1`). Now uses `((max_size * 4) / 3.0).ceil.to_i` for correct limit
- **Fixed image dimension detection**: `ImageValidator.get_image_dimensions` now parses dimensions directly from binary headers (PNG, JPEG, GIF, WebP, ICO) instead of relying on buggy `crimage` library decode. Falls back to `crimage` only for unrecognized formats

### Changed

- **Narrowed exception handling in `HtmlExtractor`**: Replaced broad `rescue ex : Exception` (with silent swallow) with typed `rescue ex : HTML5::HTMLException | URI::Error` and re-raise for unexpected exceptions

### Changed

- **Internal restructuring**: Extracted monolithic module into focused classes (`Fetcher`, `FaviconResolver`, `HtmlExtractor`, `ManifestExtractor`, `RedirectValidator`, `ImageValidator`, `DataUrlHandler`, `PlaceholderGenerator`) for better testability and separation of concerns
- **Named cache entries**: `MemoryCache` and `DnsCache` now use `CacheEntry` and `DnsEntry` records instead of positional tuples for improved type safety

### Added

- **`Vug.redirect(url)`**: Factory method for creating redirect `Result` objects
- **`ErrorType` enum**: Typed error classification on `Result` (`result.error_type`) for programmatic error handling
- **`FaviconResolver`**: Public class exposing the full fallback chain (HTML → manifest → standard paths → DuckDuckGo → Google → placeholder)
- **`DnsCache`**: Public module with 30-second TTL DNS resolution cache

## [0.4.0] - 2026-04-12

### Highlights

- Coordinated caching: prefer on-disk or config-backed storage but keep an in-memory fast-path cache for repeated lookups.
- Image processing abstraction: you can now inject a custom ImageProcessor to validate or transform images before saving.
- Safer redirect handling: redirects are validated more strictly to avoid unsafe cross-scheme or internal redirects.

### User-facing changes

- New: CacheCoordinator to bridge config-backed stores and in-memory cache (used by the fetcher by default).
- New: ImageProcessor interface and a Default implementation used by the fetcher to validate and save image bytes.
- New: RedirectHandler abstraction with a secure default implementation.

### Notes

- No breaking API changes. The public Vug module functions (`fetch`, `site`, `favicons`, `best`, `placeholder`) remain the same and work with existing Config callbacks.

### Fixed

- **Nil crash in `by_preferred_size`**: Fixed crash when collection contains favicons with unknown sizes
- **Discarded expression in `favicon_resolver.cr`**: `get || set` no-op replaced with proper `set` call
- **Deduplicated Google URL logic**: Consolidated duplicate Google favicon URL construction
- **Idiomatic Crystal patterns**: `data.size == 0` → `data.empty?` throughout codebase

## [0.2.1] - 2026-03-31

### Bug Fixes

- **Fixed SVG validator matching all XML**: `ImageValidator.svg?` matched any XML starting with `<?xml`, not just SVG. Now scans for the `<svg` tag after the XML declaration

## [0.2.0] - 2026-03-31

### Security

- **Fixed SVG XSS in placeholder generator**: Domain-derived characters are now HTML-escaped before interpolation into SVG `<text>` elements, preventing injection via crafted domain names
- **Fixed DNS rebinding TOCTOU**: Added IP re-validation at connection time in `Fetcher#fetch_single` to detect DNS rebinding attacks where initial validation resolves to a public IP but the actual request resolves to a private IP
- **DNS result caching**: Added 30-second TTL DNS cache in `UrlValidator` to avoid repeated resolution and provide consistent results during validation
- **URL-encoded domains in external service URLs**: Domains are now properly encoded via `URI.encode_www_form` / `URI.encode_path` in Google and DuckDuckGo favicon URLs to prevent parameter injection
- **Scheme downgrade protection**: `RedirectValidator` now blocks HTTPS to HTTP redirect chains

### Bug Fixes

- **Shared concurrency semaphore**: Moved `Semaphore` from per-Fetcher instance to module-level shared resource. Previously, multiple `Fetcher` instances (created during `Vug.site` fallback chain) each had their own semaphore, bypassing the 8-concurrent limit
- **Safe HTML sanitization fallback**: `HtmlExtractor#sanitize_html` now returns `""` on failure instead of returning raw unsanitized HTML
- **Typed exception handling**: Replaced 9 bare `rescue` blocks with typed rescues (`URI::Error`, `Base64::Error`, `File::Error`, `ArgumentError`, etc.) to avoid swallowing critical exceptions
- **Added missing `require "base64"`** to `placeholder_generator.cr`

### Performance

- **Efficient cache eviction**: `MemoryCache` eviction now uses explicit single-pass scan instead of `min_by` lambda with block overhead

### Added

- **`Config#max_concurrent_requests`** (default: 8): Configurable shared semaphore limit for concurrent HTTP fetches
- **`Config#image_validation_hard?`** (default: false): Opt-in CrImage decode fallback for `ImageValidator`. When false (default), only magic-byte signature checks are used for PNG, JPEG, ICO, SVG, and WebP. Set to `true` to enable CrImage-based validation for unknown formats
- **`UrlProcessor.resolve_and_normalize(href, base)`**: New helper that combines relative URL resolution and protocol-relative URL normalization in a single call
- **`API.md`**: Comprehensive API documentation

### Changed

- **`ImageValidator.valid?` and `detect_content_type`**: Default behavior no longer uses CrImage decode fallback (`hard_validation` defaults to `false`). Most favicon formats (PNG, JPEG, ICO, SVG, WebP) are covered by magic-byte checks. Enable `hard_validation: true` for CrImage fallback
- **Removed `ICO_SIGNATURE` constant**: Was misleading (two null bytes aren't a distinctive signature). ICO validation logic unchanged

### Removed

- **`Vug.fetch_for_site`** — use `Vug.site` instead
- **`Vug.fetch_all_favicons_for_site`** — use `Vug.favicons` instead
- **`Vug.fetch_best_favicon_for_site`** — use `Vug.best` instead
- **`Vug.generate_placeholder_for_site`** — use `Vug.placeholder` instead

## [0.1.5.2] - 2026-03-27

### Security & Reliability

- **Fixed mutex deadlock on FreeBSD/Docker**: Changed `Mutex.new` to `Mutex.new(:unchecked)` in `Semaphore` class to prevent recursive mutex locking during GC operations that cause deadlocks in FreeBSD jails and Docker containers

### Bug Fixes

- **Removed duplicate method definitions**: Removed duplicate `try_fallback_chain` and `generate_placeholder_fallback` methods that were causing code duplication and potential confusion

### Testing

- **New test coverage**: Added 18 new tests for fetcher logic, configuration validation, and semaphore concurrency

## [0.1.5.1] - 2026-03-26

### Security & Reliability

- **Added internal semaphore protection**: Added `Semaphore` class to limit concurrent HTTP requests to 8, preventing potential race conditions with HTTP::Client internal connection pooling

## [0.1.5.0] - 2026-03-26

### Security & Reliability

- **Verified fiber-safety of MemoryCache**: Reviewed and confirmed `MemoryCache` mutex usage is safe for concurrent fiber access in Crystal
- **No deadlock conditions**: Verified `get()` and `set()` use single isolated `synchronize` blocks with no re-entrancy

### Testing

- **Fiber-safety tests**: Added 3 new concurrent access tests proving `MemoryCache` handles multiple fibers safely:
  - Concurrent get/set from multiple fibers without deadlock
  - Concurrent gets and sets interleaving without deadlock
  - Consistency under concurrent set operations on same key

## [0.1.4.1] - 2026-03-19

### Fixed

- **Fixed `sanitize_url` undefined method error**: Replaced references to private `sanitize_url` with `UrlProcessor.sanitize_feed_url` in `try_fallback_chain` and `generate_placeholder_fallback` methods
- **Fixed `else nil` blocks**: Removed redundant `else nil` blocks in `get_gray_placeholder_fallback_url` method

### Added

- **Comprehensive tests**: Added 5 new integration tests for feed URL handling across all main Vug module methods to prevent regression

## [0.1.4] - 2026-03-19

### Performance Improvements

- **URL processing optimization**: Eliminated repeated URL sanitization operations by caching sanitized URLs within method execution flows
- **HttpClientFactory reuse**: Reduced redundant object creation by reusing HttpClientFactory instances within single favicon fetching operations  
- **MemoryCache monotonic time**: Replaced `Time.local` with monotonic time tracking for consistent cache TTL behavior across different timezone configurations

### Security & Reliability Enhancements

- **Gray placeholder fallback safety**: Replaced recursive fetch calls with iterative loop to prevent potential stack overflow scenarios
- **Recursion depth protection**: Added maximum attempts limit (3) for gray placeholder fallback to prevent infinite loops
- **Consistent URL validation**: Unified URL processing logic across all modules using shared `UrlProcessor` utilities

### Code Quality & Maintainability

- **Centralized URL processing**: Extracted duplicated URL normalization and host extraction logic into `UrlProcessor` module
- **Improved error handling**: Enhanced edge case validation in `PlaceholderGenerator` for empty or whitespace-only domains
- **Reduced code duplication**: Eliminated redundant string operations and factory instantiation across the codebase

### Testing

- **Added comprehensive tests**: 11 new test cases for `UrlProcessor` methods covering feed URL handling, host extraction, and sanitization
- **Maintained 100% test coverage**: All existing functionality preserved with no regressions
- **Enhanced test robustness**: Better validation of edge cases and error conditions

### Compatibility

- **Crystal 1.18.2 support**: Maintained full compatibility with Crystal 1.18.2 (no `Time::Instant` usage)
- **Backward compatible API**: No breaking changes to public interfaces
- **Dependency updates**: No dependency changes required

## [0.1.3.4] - 2026-03-18

### Bug Fixes

- **Constructor parameter patterns**: Fixed instance variable usage in constructor parameters across Fetcher, CacheManager, HtmlExtractor, and ManifestExtractor for consistent and safe dependency injection
- **Test coverage**: Added comprehensive initialization tests for all extractor classes to prevent regression

## [0.1.3.3] - 2026-03-18

### Bug Fixes

- **ManifestExtractor nil handling**: Fixed nil handling in ManifestExtractor dependency injection in HtmlExtractor constructor

## [0.1.3.2] - 2026-03-18

### Bug Fixes

- **HtmlExtractor initialization**: Fixed nil handling in HttpClientFactory dependency injection to prevent compilation errors

## [0.1.3.1] - 2026-03-18

### Bug Fixes

- **Dependency compatibility**: Added explicit version constraint `~> 1.0` for crimage dependency to prevent compatibility issues with other programs using different versions of crimage

## [0.1.3] - 2026-03-18

### Improvements

- **Code quality and maintainability**: Implemented comprehensive refactoring to address DRY violations and improve code organization
- **HTTP client factory**: Centralized HTTP client creation with consistent configuration across all components
- **URL processor module**: Unified URL normalization, resolution, and validation logic in a single module
- **Cache manager**: Standardized cache access patterns with unified config-based and memory cache handling  
- **Redirect validator**: Extracted redirect validation logic into dedicated service class
- **Dependency injection**: Improved testability and maintainability through proper dependency injection
- **File organization**: Moved FaviconInfo to its own file for better separation of concerns
- **Dependency cleanup**: Removed unused lexbor dependency and updated to crystal-html5 exclusively

### Performance

- **Reduced code duplication**: Eliminated redundant logic across multiple files
- **Improved maintainability**: Smaller, focused files with clear single responsibilities
- **Better error handling**: Standardized error contexts and logging patterns

### Code Quality

- **All files under 200 lines**: Improved readability and maintainability
- **Function naming consistency**: All public API function names are 1-3 words as recommended
- **Idiomatic Crystal**: Follows Crystal best practices and coding conventions

## [0.1.0] - 2026-03-17

### Features

- **Complete favicon fetching library** with pluggable storage callbacks
- **HTML extraction** using high-performance HTML parser with CSS selectors
- **Web App Manifest support** for parsing manifest files and extracting icon metadata
- **Multiple favicon collection** to gather favicons from multiple sources with metadata (sizes, types, purposes)
- **Intelligent favicon selection** with methods to choose best, largest, or preferred size favicons
- **Comprehensive fallback chain**: HTML extraction → Manifest extraction → Standard paths → DuckDuckGo → Google S2 → Placeholder generation
- **Data URL support** for handling inline base64 encoded favicons like `data:image/png;base64,...`
- **Advanced image validation** supporting PNG, JPEG, GIF, BMP, TIFF, WebP, ICO, and SVG formats
- **Image dimension detection** to extract and log actual image dimensions  
- **Placeholder generation** creating default SVG favicons with domain letter when no real favicon is found
- **In-memory caching** with TTL and size limits for performance optimization
- **SSRF protection** with security validation to prevent server-side request forgery attacks
- **Pluggable storage interface** via callbacks for disk, S3, memory, or custom storage solutions
- **Comprehensive error handling** with detailed error reporting and logging callbacks
- **Configurable options** for timeouts, limits, and behavior tuning

### API

- **Direct URL fetching**: `Vug.fetch(url)`
- **Site favicon fetching**: `Vug.site(site_url)`  
- **Favicon collection**: `Vug.favicons(site_url)`
- **Best favicon fetching**: `Vug.best(site_url)`
- **Placeholder generation**: `Vug.placeholder(site_url)`
- **Configurable callbacks**: `on_save`, `on_load`, `on_debug`, `on_error`, `on_warning`
- **FaviconCollection**: Methods for selecting best, largest, or preferred size favicons
- **Result types**: Success, failure, and redirect handling with proper error messages

### Security

- **URL validation**: Blocks dangerous schemes (file://, ftp://, etc.)
- **Private IP blocking**: Prevents access to localhost, 10.x.x.x, 192.168.x.x, and other private ranges
- **Redirect validation**: Ensures safe redirects between domains

### Dependencies

- **sanitize**: HTML sanitization for security
- **html5**: HTML parsing (crystal-html5) for cross-platform compatibility
- **crimage**: Image validation and dimension detection
- **Crystal 1.18+**: Modern Crystal features

### Testing

- **43 comprehensive tests** covering all major functionality
- **Integration tests** for end-to-end workflows
- **Security tests** for SSRF protection
- **Edge case handling** for malformed inputs

This is the first official release of vug.cr!
