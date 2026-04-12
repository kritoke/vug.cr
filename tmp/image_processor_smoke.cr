require "../src/vug.cr"
require "digest"
require "crimage"

config = Vug::Config.new(
  on_load: ->(_u : String) : String? { nil },
  on_save: ->(_u : String, _data : Bytes, _ct : String) { "/tmp/#{Digest::SHA256.hexdigest(_u)}".as(String?) }
)

mem = Vug::MemoryCache.new
cm = Vug::CacheManager.new(config, mem)
processor = Vug::ImageProcessor::Default.new(config, cm)

# Create a minimal 2x2 PNG using CrImage
rect = CrImage.rect(0, 0, 2, 2)
rgba = CrImage::RGBA.new(rect)
io = IO::Memory.new
CrImage::PNG.write(io, rgba)
png_data = io.to_slice

result = processor.process_bytes("https://example.com/favicon.png", png_data, "image/png")
puts "process_bytes success? #{result.success?} saved_path=#{result.local_path}"
