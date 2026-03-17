# Changelog

## [0.1.0] - 2026-03-17

### Added
- **Complete favicon fetching library** with pluggable storage callbacks
- **HTML extraction**: Extract favicon URLs from HTML pages using Lexbor CSS selectors
- **Web App Manifest support**: Parse manifest files and extract icon information
- **Multiple favicon collection**: Gather favicons from multiple sources with metadata
- **Intelligent selection**: Choose best, largest, or preferred size favicons
- **Comprehensive fallback chain**: HTML → Manifest → Standard paths → DuckDuckGo → Google S2 → Placeholder
- **Data URL support**: Handle inline base64 encoded favicons
- **Image validation**: Validate favicon images using crimage (PNG, JPEG, GIF, BMP, TIFF, WebP, ICO, SVG)
- **Image dimension detection**: Extract and log image dimensions
- **Placeholder generation**: Create default SVG favicons with domain letter when no real favicon found
- **In-memory caching**: TTL and size-limited cache for performance
- **SSRF protection**: Security validation to prevent server-side request forgery
- **Pluggable storage**: Callback-based storage interface for disk, S3, memory, etc.
- **Comprehensive error handling**: Detailed error reporting and logging callbacks
- **Configuration options**: Tunable timeouts, limits, and behavior

### Features
- **Direct URL fetching**: `Vug.fetch(url)`
- **Site favicon fetching**: `Vug.fetch_for_site(site_url)`  
- **Best favicon fetching**: `Vug.fetch_best_favicon_for_site(site_url)`
- **Favicon collection**: `Vug.fetch_all_favicons_for_site(site_url)`
- **Placeholder generation**: `Vug.generate_placeholder_for_site(site_url)`

### API
- **Configurable callbacks**: `on_save`, `on_load`, `on_debug`, `on_error`, `on_warning`
- **FaviconCollection**: Methods for selecting best, largest, or preferred size favicons
- **Result types**: Success, failure, and redirect handling with proper error messages

### Security
- **URL validation**: Blocks dangerous schemes (file://, ftp://, etc.)
- **Private IP blocking**: Prevents access to localhost, 10.x.x.x, 192.168.x.x, etc.
- **Redirect validation**: Ensures safe redirects between domains

### Dependencies
- **Lexbor**: High-performance HTML parsing
- **Sanitize**: HTML sanitization for security
- **Crimage**: Image validation and dimension detection
- **Crystal 1.18+**: Modern Crystal features

### Testing
- **43 comprehensive tests** covering all major functionality
- **Integration tests** for end-to-end workflows
- **Security tests** for SSRF protection
- **Edge case handling** for malformed inputs

This is the first official release of vug.cr!