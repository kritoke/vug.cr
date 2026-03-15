# vug.cr

Favicon fetching library with pluggable storage callbacks.

## Features

- Fetch favicons from URLs with proper HTTP client handling
- Extract favicon URLs from HTML pages
- Fallback chain: HTML extraction → /favicon.ico → Google S2 service
- Pluggable storage via callbacks (disk, memory, S3, etc.)
- Built-in image validation (PNG, JPEG, ICO, SVG, WebP)
- In-memory caching with TTL and size limits
- Comprehensive error handling and logging callbacks

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  vug:
    github: kritoke/vug.cr
```

## Usage

```crystal
require "vug"

# Configure with callbacks
config = Vug::Config.new(
  on_save: ->(url : String, data : Bytes, content_type : String) do
    # Save to disk, S3, etc.
    "/favicons/#{Digest::SHA256.hexdigest(url)[0...16]}.#{extension}"
  end,
  on_load: ->(url : String) do
    # Load from disk, S3, etc.
    "/favicons/#{Digest::SHA256.hexdigest(url)[0...16]}.png"
  end,
  on_debug: ->(msg : String) { puts msg },
  on_error: ->(ctx : String, ex : Exception) { puts "#{ctx}: #{ex.message}" }
)

# Fetch favicon from direct URL
result = Vug.fetch("https://example.com/favicon.ico", config)
if result.success?
  puts "Favicon saved to: #{result.local_path}"
end

# Fetch favicon for site (tries multiple strategies)
result = Vug.fetch_for_site("https://example.com", config)
if result.success?
  puts "Site favicon saved to: #{result.local_path}"
end
```

## API

### `Vug.fetch(url, config, cache)`

Fetches a favicon from a direct URL.

### `Vug.fetch_for_site(site_url, config, cache)`

Fetches a favicon for a site using the fallback chain:
1. Extract from HTML `<link rel="icon">` tags
2. Try standard paths (`/favicon.ico`, `/favicon.png`, etc.)
3. Fall back to Google S2 favicon service

### `Vug::Config`

Configuration with callback interfaces:
- `on_save`: Called when favicon data needs to be persisted
- `on_load`: Called when checking for cached favicons
- `on_debug`: Debug logging
- `on_error`: Error logging
- `on_warning`: Warning logging

### `Vug::Result`

Result type with helper methods:
- `success?` - Returns true if favicon was successfully fetched and saved
- `failure?` - Returns true if there was an error
- `redirect?` - Returns true if URL redirected (internal use)

## Storage Callbacks

The library is storage-agnostic. You provide callbacks to handle persistence:

- **`on_save`**: `(url, data, content_type) -> saved_path`
- **`on_load`**: `(url) -> saved_path_or_nil`

This allows you to store favicons on disk, in S3, in a database, or in memory.

## Testing

Run specs with:

```bash
crystal spec
```

## License

MIT