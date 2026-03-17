# vug.cr v0.1.0

**First official release** of the comprehensive favicon fetching library for Crystal! 🎉

## 🔥 Key Features

### 🦅 Complete Favicon Fetching
- **Multi-strategy approach**: HTML extraction → Web App Manifest → Standard paths → DuckDuckGo → Google S2 → Placeholder generation
- **Direct URL fetching**: `Vug.fetch("https://example.com/favicon.ico")`
- **Site-based fetching**: `Vug.fetch_for_site("https://example.com")`
- **Best favicon selection**: `Vug.fetch_best_favicon_for_site("https://example.com")`

### 🕸️ Advanced Parsing & Extraction
- **HTML extraction**: Uses high-performance [Lexbor](https://github.com/kostya/lexbor) parser with CSS selectors
- **Web App Manifest support**: Parses manifest files and extracts icon metadata
- **Multiple favicon collection**: Gather all available favicons with sizes, types, and purposes
- **Intelligent selection**: Choose best (preferring "any" size), largest, or preferred dimensions

### 🔒 Security First
- **SSRF Protection**: Blocks dangerous schemes (`file://`, `ftp://`, etc.)
- **Private IP Blocking**: Prevents access to localhost, 10.x.x.x, 172.16-31.x.x, 192.168.x.x ranges
- **Redirect Validation**: Ensures safe redirects between domains
- **HTML Sanitization**: Uses [Sanitize](https://github.com/straight-shoota/sanitize) for secure parsing

### 🖼️ Image Intelligence
- **Format Support**: PNG, JPEG, GIF, BMP, TIFF, WebP, ICO, SVG
- **Image Validation**: Validates actual image content using [Crimage](https://github.com/naqvis/crimage)
- **Dimension Detection**: Extracts and logs image dimensions automatically
- **Placeholder Generation**: Creates default SVG favicons with domain letter when no real favicon found

### 💾 Storage Agnostic
- **Pluggable callbacks**: Provide your own storage logic via `on_save` and `on_load` callbacks
- **Works with**: Disk, S3, databases, memory, or any custom storage
- **In-memory caching**: Built-in TTL and size-limited cache for performance

### 🧪 Comprehensive Testing
- **43 passing tests** covering all major functionality
- **Security tests** for SSRF protection scenarios  
- **Integration tests** for end-to-end workflows
- **Edge case handling** for malformed inputs and network errors

## 📦 Installation

Add to your `shard.yml`:

```yaml
dependencies:
  vug:
    github: kritoke/vug.cr
```

## 🚀 Quick Start

```crystal
require "vug"

# Configure storage callbacks
config = Vug::Config.new(
  on_save: ->(url : String, data : Bytes, content_type : String) do
    # Save favicon to disk/S3/database
    path = "/favicons/#{Digest::SHA256.hexdigest(url)[0...16]}.#{extension}"
    File.write(path, data)
    path
  end,
  on_load: ->(url : String) do
    # Load from storage
    path = "/favicons/#{Digest::SHA256.hexdigest(url)[0...16]}.png"
    File.exists?(path) ? path : nil
  end
)

# Fetch favicon for a site
result = Vug.fetch_for_site("https://example.com", config)
if result.success?
  puts "Favicon saved to: #{result.local_path}"
end
```

## 📚 Full Documentation

See the [README](README.md) for complete API documentation and usage examples.

## 🙏 Acknowledgements

Built with ❤️ using:
- [Lexbor](https://github.com/kostya/lexbor) - High-performance HTML parsing
- [Sanitize](https://github.com/straight-shoota/sanitize) - HTML sanitization  
- [Crimage](https://github.com/naqvis/crimage) - Image validation and processing

---

Ready for production use! 🚀