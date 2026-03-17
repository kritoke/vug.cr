# vug.cr

Favicon fetching library with pluggable storage callbacks.

## Features

- Fetch favicons from URLs with proper HTTP client handling
- Extract favicon URLs from HTML pages using proper CSS selectors (Lexbor)
- Web App Manifest parsing support (extracts icons from manifest files)
- Multiple favicon collection and intelligent selection (best, largest, by size)
- Size attribute extraction and utilization from HTML and manifest
- DuckDuckGo favicon API support as additional fallback
- Base64 data URL support (handles inline favicons like `data:image/png;base64,...`)
- Advanced image validation using crimage (supports PNG, JPEG, GIF, BMP, TIFF, WebP, ICO, SVG)
- Image dimension detection and logging
- **Placeholder generation** - creates default SVG favicons with domain letter when no real favicon is found
- Fallback chain: HTML extraction → Manifest extraction → Standard paths → DuckDuckGo → Google S2 → Placeholder
- Pluggable storage via callbacks (disk, memory, S3, etc.)
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

# Fetch favicon for site (tries multiple strategies, generates placeholder if none found)
result = Vug.site("https://example.com", config)
if result.success?
  puts "Site favicon saved to: #{result.local_path}"
end

# Get all available favicons for intelligent selection
collection = Vug.favicons("https://example.com", config)
if collection
  puts "Found #{collection.size} favicons"
  best = collection.best
  largest = collection.largest
end

# Fetch only the best favicon directly
result = Vug.best("https://example.com", config)

# Generate placeholder favicon directly (useful for sites with no favicons)
result = Vug.placeholder("https://example.com", config)
```

## API

### `Vug.fetch(url, config, cache)`
Fetches a favicon from a direct URL.

### `Vug.site(site_url, config, cache)`
Fetches a favicon for a site using the fallback chain:
1. Extract from HTML `<link rel="icon">` tags
2. Extract from Web App Manifest (`<link rel="manifest">`)
3. Try standard paths (`/favicon.ico`, `/favicon.png`, etc.)
4. Fall back to DuckDuckGo favicon service
5. Fall back to Google S2 favicon service

### `Vug.favicons(site_url, config)`
Returns a `FaviconCollection` containing all discovered favicons with metadata (sizes, types, etc.).

### `Vug.best(site_url, config, cache)`
Fetches only the best available favicon based on size and quality heuristics.

### `Vug.placeholder(site_url, config, cache)`
Generates a default SVG favicon with the domain's first letter.

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
