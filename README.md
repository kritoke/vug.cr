# vug.cr

Favicon fetching library with pluggable storage callbacks.

## Features

- Fetch favicons from direct URLs
- Extract favicon URLs from HTML pages (`<link rel="icon">`, `<link rel="apple-touch-icon">`, etc.)
- Web App Manifest parsing for icon extraction
- Multiple favicon collection with intelligent best/largest/by-size selection
- DuckDuckGo and Google favicon service fallbacks
- Inline base64 data URL support (`data:image/png;base64,...`)
- SVG placeholder generation when no real favicon is found
- In-memory caching with TTL and size limits
- SSRF protection with DNS rebinding detection
- Pluggable storage via callbacks (disk, S3, database, memory — your choice)
 - Coordinated caching (in-memory + config-backed) to prefer existing on-disk stores
 - Image processing abstraction with a default processor for validation and saving
 - Safer redirect handling with stricter URL validation to prevent unsafe redirects

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  vug:
    github: kritoke/vug.cr
```

## Quick Start

```crystal
require "vug"

# Minimal — no config needed
result = Vug.site("https://example.com")
if result.success?
  puts result.local_path
end
```

## With Storage Callbacks

```crystal
require "vug"

config = Vug::Config.new(
  on_save: ->(url : String, data : Bytes, content_type : String) {
    path = "/tmp/favicons/#{Digest::SHA256.hexdigest(url)}.png"
    File.write(path, data)
    path  # return the saved path
  },
  on_load: ->(url : String) {
    path = "/tmp/favicons/#{Digest::SHA256.hexdigest(url)}.png"
    File.exists?(path) ? path : nil  # return path or nil
  },
  on_debug: ->(msg : String) { Log.debug { msg } },
)

# Fetch favicon for a website (tries HTML, manifest, fallbacks, placeholder)
result = Vug.site("https://example.com", config)
if result.success?
  puts "Saved to: #{result.local_path}"
elsif result.failure?
  puts "Error: #{result.error}"
end

# Fetch from a direct URL
result = Vug.fetch("https://example.com/favicon.ico", config)

# Get all available favicons for custom selection
collection = Vug.favicons("https://example.com", config)
if collection
  best = collection.best       # highest quality available
  largest = collection.largest # biggest pixel area
  puts "Found #{collection.size} favicons"
end

# Generate a placeholder SVG (first letter of domain)
result = Vug.placeholder("https://example.com", config)
```

## Caching

Pass a `MemoryCache` to share cache across calls:

```crystal
cache = Vug::MemoryCache.new(size_limit: 5_000_000, entry_ttl: 1.hour)

result1 = Vug.site("https://example.com", config, cache) # fetches
result2 = Vug.site("https://example.com", config, cache) # cache hit
```

## Configuration

All options have sensible defaults. Override only what you need:

```crystal
config = Vug::Config.new(
  timeout: 15.seconds,
  max_redirects: 5,
  max_size: 200 * 1024,           # 200KB max favicon size
  user_agent: "MyApp/1.0",
)
```

See [API.md](API.md) for the full configuration reference and advanced usage.

What's new in v0.4.0

- Coordinated caching that prefers your configured on-disk storage while keeping a small in-memory cache for speed.
- Image processing is pluggable — you can provide a custom processor to validate or transform images before they are saved.
- Improved redirect handling to prevent unsafe redirects.

## License

MIT
