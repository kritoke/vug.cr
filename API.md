# API Reference

Complete public API documentation for vug.cr.

## Table of Contents

- [Module Methods](#module-methods)
- [Result](#result)
- [Config](#config)
- [MemoryCache](#memorycache)
- [FaviconCollection](#faviconcollection)
- [FaviconInfo](#faviconinfo)
- [ImageValidator](#imagevalidator)
- [UrlProcessor](#urlprocessor)
- [UrlValidator](#urlvalidator)

---

## Module Methods

All methods are on the `Vug` module.

### `Vug.fetch(url, config = Config.new, cache = nil)`

Fetches a favicon from a direct URL. Validates the URL for SSRF protection before making the request.

```crystal
result = Vug.fetch("https://example.com/favicon.ico")
```

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `url` | `String` | (required) | Direct URL to a favicon file |
| `config` | `Config` | `Config.new` | Configuration object |
| `cache` | `MemoryCache?` | `nil` | Optional shared cache |

**Returns:** `Result`

### `Vug.site(site_url, config = Config.new, cache = nil)`

Fetches a favicon for a website using a multi-strategy fallback chain:

1. HTML extraction (`<link rel="icon">`, `<link rel="apple-touch-icon">`, etc.)
2. Web App Manifest parsing
3. Standard paths (`/favicon.ico`, `/favicon.png`, `/apple-touch-icon.png`)
4. DuckDuckGo favicon service
5. Google S2 favicon service
6. SVG placeholder generation (first letter of domain)

Always returns a result — either a real favicon or a generated placeholder.

```crystal
result = Vug.site("https://example.com")
```

**Parameters:** Same as `Vug.fetch`

**Returns:** `Result`

### `Vug.favicons(site_url, config = Config.new)`

Extracts all favicon candidates from a website's HTML and manifest. Does not fetch the favicons — returns metadata only.

```crystal
collection = Vug.favicons("https://example.com")
if collection
  collection.all.each do |favicon|
    puts "#{favicon.url} — #{favicon.sizes}"
  end
end
```

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `site_url` | `String` | (required) | Website URL |
| `config` | `Config` | `Config.new` | Configuration object |

**Returns:** `FaviconCollection?` — `nil` if no favicons found

### `Vug.best(site_url, config = Config.new, cache = nil)`

Fetches only the best available favicon for a website. Returns failure if no favicon found (unlike `site`, which generates a placeholder).

```crystal
result = Vug.best("https://example.com")
```

**Parameters:** Same as `Vug.fetch`

**Returns:** `Result`

### `Vug.placeholder(site_url, config = Config.new, cache = nil)`

Generates an SVG placeholder favicon — a colored circle with the first letter of the domain.

```crystal
result = Vug.placeholder("https://example.com")
# result.bytes contains SVG data
# result.content_type is "image/svg+xml"
```

**Parameters:** Same as `Vug.fetch`

**Returns:** `Result`

### `Vug.google_favicon_url(domain)`

Returns the Google S2 favicon URL for a domain. Useful if you want to use Google's service directly.

```crystal
Vug.google_favicon_url("example.com")
# => "https://www.google.com/s2/favicons?domain=example.com&sz=256"
```

### `Vug.duckduckgo_favicon_url(domain)`

Returns the DuckDuckGo favicon URL for a domain.

```crystal
Vug.duckduckgo_favicon_url("example.com")
# => "https://icons.duckduckgo.com/ip3/example.com.ico"
```

---

## Result

An immutable record returned by all fetching methods.

```crystal
record Vug::Result,
  url : String?,        # The resolved favicon URL
  local_path : String?, # Path returned by on_save callback
  content_type : String?,
  bytes : Bytes?,
  error : String?,
  error_type : ErrorType?
```

### Factory Methods

| Method | Description |
|--------|-------------|
| `Vug.success(url, local_path, content_type?, bytes?)` | Create a success result |
| `Vug.failure(error, url?, error_type?)` | Create a failure result |
| `Vug.redirect(url)` | Create a redirect result (internal use) |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `success?` | `Bool` | `true` if `local_path` is set and no error |
| `failure?` | `Bool` | `true` if `error` is set |
| `redirect?` | `Bool` | `true` if URL set but no path/error (internal use) |

### Example

```crystal
case result
when .success?
  puts result.local_path
  puts result.content_type   # e.g. "image/png"
  puts result.bytes          # raw image data, if available
when .failure?
  puts result.error          # e.g. "HTTP 404", "Invalid URL"
  puts result.error_type     # e.g. :http_error, :invalid_url
end
```

---

## Config

Configuration object with sensible defaults. All constructor parameters are optional.

```crystal
config = Vug::Config.new(
  timeout: 30.seconds,
  on_save: ->(url : String, data : Bytes, content_type : String) {
    path = "/tmp/#{Digest::SHA256.hexdigest(url)[0..7]}.png"
    File.write(path, data)
    path
  },
)
```

### Constructor Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `timeout` | `Time::Span` | `30.seconds` | Total request timeout |
| `connect_timeout` | `Time::Span` | `10.seconds` | Connection establishment timeout |
| `max_redirects` | `Int32` | `10` | Maximum redirect hops |
| `max_size` | `Int32` | `102_400` (100KB) | Maximum favicon size in bytes |
| `user_agent` | `String` | Chrome UA | User-Agent header |
| `accept_language` | `String` | `"en-US,en;q=0.9"` | Accept-Language header |
| `cache_size_limit` | `Int32` | `10_485_760` (10MB) | MemoryCache size limit |
| `cache_entry_ttl` | `Time::Span` | `7.days` | MemoryCache entry TTL |
| `gray_placeholder_size` | `Int32` | `198` | Size threshold for Google gray placeholder detection |
| `max_concurrent_requests` | `Int32` | `8` | Shared semaphore limit for concurrent HTTP fetches |

### Callbacks

| Callback | Signature | Description |
|----------|-----------|-------------|
| `on_save` | `(url : String, data : Bytes, content_type : String) -> String?` | Save fetched data. Return the saved path or `nil` on failure. |
| `on_load` | `(url : String) -> String?` | Check/load cached path. Return path or `nil` if not cached. |
| `on_debug` | `(message : String) -> Nil` | Debug logging |
| `on_error` | `(context : String, message : String) -> Nil` | Error logging |
| `on_warning` | `(message : String) -> Nil` | Warning logging |

### Properties

All constructor parameters are exposed as mutable properties. You can also set them after construction:

```crystal
config = Vug::Config.new
config.timeout = 10.seconds
config.on_debug = ->(msg : String) { puts msg }
```

---

## MemoryCache

Thread-safe in-memory cache with TTL expiration and size-based eviction. Designed to be shared across multiple fetch calls.

```crystal
cache = Vug::MemoryCache.new(
  size_limit: 5_000_000,  # 5MB
  entry_ttl: 1.hour,
)

result = Vug.site("https://example.com", config, cache)
result = Vug.site("https://example.com", config, cache) # cache hit
```

### Constructor Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `size_limit` | `Int32` | `10_485_760` (10MB) | Maximum total cache size in bytes |
| `entry_ttl` | `Time::Span` | `7.days` | Time-to-live per entry |

### Methods

| Method | Description |
|--------|-------------|
| `get(url : String) : String?` | Get cached path, returns `nil` if missing or expired |
| `set(url : String, local_path : String) : Nil` | Cache a path. Only absolute paths are stored. |
| `clear : Nil` | Clear all entries |
| `size : Int32` | Number of entries currently cached |

---

## FaviconCollection

A collection of `FaviconInfo` entries extracted from a website.

```crystal
collection = Vug.favicons("https://example.com")
if collection
  collection.best           # highest priority
  collection.largest        # biggest pixel area
  collection.by_preferred_size(32, 32)  # closest to 32x32
  collection.all            # Array(FaviconInfo)
  collection.size           # count
end
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `best` | `FaviconInfo?` | Best favicon by size/priority heuristics |
| `largest` | `FaviconInfo?` | Largest favicon by pixel area |
| `by_preferred_size(w, h)` | `FaviconInfo?` | Favicon closest to requested dimensions |
| `all` | `Array(FaviconInfo)` | All favicons (cloned array) |
| `size` | `Int32` | Number of favicons |
| `empty?` | `Bool` | Whether collection is empty |

---

## FaviconInfo

A single favicon entry with metadata.

```crystal
record Vug::FaviconInfo,
  url : String,
  sizes : String?,
  type : String?,
  purpose : String?
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `size_pixels` | `Int32?` | Largest dimension area (width * height), or `nil` |
| `has_any_size?` | `Bool` | `true` if sizes is `"any"` |

### Example

```crystal
favicon = collection.best
if favicon
  favicon.url         # "https://example.com/icon-192.png"
  favicon.sizes       # "192x192"
  favicon.type        # "image/png"
  favicon.size_pixels # 36864 (192 * 192)
end
```

---

## ErrorType

Typed error enum on `Result` for programmatic error handling.

```crystal
case result.error_type
when :invalid_url         then # URL failed validation
when :timeout             then # request timed out
when :too_many_redirects  then # exceeded max_redirects
when :http_error          then # non-success HTTP status
when :invalid_image       then # failed image validation
when :no_favicon_found    then # all strategies exhausted
when :dns_revalidation_failed then # possible DNS rebinding
else                           # other errors
end
```

### Variants

| Value | Description |
|-------|-------------|
| `:invalid_url` | URL failed validation (scheme, host, or SSRF check) |
| `:timeout` | Request exceeded timeout |
| `:too_many_redirects` | Redirect chain too long |
| `:too_many_gray_placeholder_attempts` | Google gray placeholder loop exhausted |
| `:dns_revalidation_failed` | DNS rebinding detected |
| `:invalid_redirect` | Redirect target failed SSRF validation |
| `:empty_response` | Server returned empty body |
| `:invalid_image` | Response failed image validation |
| `:save_failed` | `on_save` callback returned `nil` |
| `:http_error` | Non-success HTTP status |
| `:fetch_error` | Network/IO error |
| `:no_favicon_found` | No favicon found and no fallback available |
| `:placeholder_generation_failed` | SVG placeholder generation failed |
| `:unknown` | Unclassified error |

---

## ImageValidator

Module for validating image data and detecting content types. Uses magic-byte signature checks by default; optionally falls back to CrImage decode.

### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `valid?` | `(data : Bytes, hard_validation : Bool = false) : Bool` | Check if bytes represent a valid image |
| `detect_content_type` | `(data : Bytes, hard_validation : Bool = false) : String` | Return MIME type string |
| `png?` | `(data : Bytes) : Bool` | Check PNG signature |
| `jpeg?` | `(data : Bytes) : Bool` | Check JPEG signature |
| `ico?` | `(data : Bytes) : Bool` | Check ICO signature |
| `svg?` | `(data : Bytes) : Bool` | Check SVG signature |
| `webp?` | `(data : Bytes) : Bool` | Check WebP signature |
| `get_image_dimensions` | `(data : Bytes) : {Int32, Int32}?` | Extract width/height (uses CrImage) |

**`hard_validation`**: When `true`, uses CrImage to decode unknown formats as a fallback. Default is `false` (magic bytes only).

---

## UrlProcessor

URL normalization, resolution, and validation utilities.

### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `sanitize_feed_url` | `(url : String) : String` | Remove `/feed/` suffix from URLs |
| `resolve_and_normalize` | `(href : String, base : String, base_scheme : String = "https") : String` | Resolve relative URLs and normalize protocol-relative URLs |
| `resolve_url` | `(url : String, base : String) : String` | Resolve relative URL against base |
| `normalize_url` | `(url : String, base_scheme : String = "https") : String` | Convert `//` protocol-relative URLs to absolute |
| `valid_scheme?` | `(url : String) : Bool` | Check for http/https scheme |
| `extract_host_from_url` | `(url : String) : String?` | Extract hostname, handling feed URLs |

---

## UrlValidator

SSRF protection. Validates URLs against private IP ranges, localhost, and dangerous schemes.

### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `valid_url?` | `(url : String) : Bool` | Validate URL is safe to fetch (scheme + host + IP check) |
| `revalidate_url?` | `(url : String) : Bool` | Re-check DNS at connection time (DNS rebinding protection) |
| `private_ip?` | `(ip : String) : Bool` | Check if IP string is in private ranges |
| `resolve_ips_cached` | `(host : String) : Array(String)` | Resolve hostname to IPs with 30s cache |

### Protected Ranges

- `127.0.0.0/8` (loopback)
- `10.0.0.0/8` (Class A private)
- `172.16.0.0/12` (Class B private)
- `192.168.0.0/16` (Class C private)
- `0.0.0.0` (unspecified)
- `::1` (IPv6 loopback)
- `fc00::/7` (IPv6 unique local)
- `fe80::/10` (IPv6 link-local)
- `::ffff:*` (IPv4-mapped IPv6)
- `.local` domains

---

## CacheCoordinator

Lightweight helper that bridges your configured on-disk/config-backed store (via Config callbacks) and an optional in-memory cache. The fetcher uses this to prefer existing saved files while still offering a fast in-memory hit for repeat requests.

### Usage

You normally don't need to construct this directly; the Fetcher uses it by default. If you do, construct with a Config and an optional MemoryCache and CacheManager:

```crystal
coord = Vug::CacheCoordinator.new(config, memory_cache, cache_manager)
path = coord.fetch_from_cache(url) # -> String? (path if found)
coord.store_to_cache(url, path)    # stores to both configured store and memory cache
```

## ImageProcessor

Abstraction for validating and saving image bytes. The Fetcher delegates image validation and saving to an ImageProcessor so you can provide custom logic (e.g., transform images, save to external services, or apply additional validation).

The default processor validates the bytes, calls `Config.on_save` to persist them, and returns a Result.

### Interface (conceptual)

| Method | Signature | Description |
|--------|-----------|-------------|
| `process_bytes` | `(url : String, data : Bytes, content_type : String) : Result` | Validate and store image bytes, returning a `Result` (success/failure) |

### Example

```crystal
class MyProcessor < Vug::ImageProcessor
  def process_bytes(url, data, content_type)
    # custom validation/transformation
    Vug.success(url, "/path/to/saved", content_type, data)
  end
end

fetcher = Vug::Fetcher.new(config, nil, nil, nil, nil, nil, MyProcessor.new)
```

## RedirectHandler

Redirect handling is pluggable so you can customize how redirect URLs are evaluated before following them. The default handler applies conservative checks to avoid unsafe cross-scheme downgrades or redirects into private/reserved IP ranges.

### Default behavior

- Validates redirect targets with the UrlValidator
- Blocks redirects that downgrade from HTTPS to HTTP
- Allows custom handlers to implement alternate policies

### Usage

You can provide a custom RedirectHandler implementation to Fetcher during construction. The handler must expose a `validate_redirect_url(original_url, new_url)`-like method that returns `true` to allow following the redirect, `false` to block it.


## Migration from 0.1.x

### Renamed Methods (0.2.0)

| Old | New |
|-----|-----|
| `Vug.fetch_for_site(...)` | `Vug.site(...)` |
| `Vug.fetch_all_favicons_for_site(...)` | `Vug.favicons(...)` |
| `Vug.fetch_best_favicon_for_site(...)` | `Vug.best(...)` |
| `Vug.generate_placeholder_for_site(...)` | `Vug.placeholder(...)` |

### Behavioral Changes

- `ImageValidator.valid?` no longer falls back to CrImage by default. Pass `hard_validation: true` if you need CrImage-based validation.
- `sanitize_html` returns `""` on failure instead of raw HTML (security hardening).
