# Changelog

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