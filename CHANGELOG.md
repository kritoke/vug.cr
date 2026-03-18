# Changelog

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

### Testing
- **Comprehensive test coverage**: Added tests for all new utility modules (HttpClientFactory, UrlProcessor, CacheManager, RedirectValidator)
- **Maintained compatibility**: All existing tests continue to pass with no regressions
- **Integration testing**: Verified end-to-end functionality with complex scenarios

### Code Quality
- **All files under 200 lines**: Improved readability and maintainability
- **Function naming consistency**: All public API function names are 1-3 words as recommended
- **Idiomatic Crystal**: Follows Crystal best practices and coding conventions
- **Zero linter warnings**: Clean ameba linting results with no code smells

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