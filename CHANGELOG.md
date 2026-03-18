# Changelog

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