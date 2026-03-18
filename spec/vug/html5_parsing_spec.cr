require "../spec_helper"
require "../../src/vug/html_extractor"
require "../../src/vug/manifest_extractor"

def get_attr_val(node : HTML5::Node, key : String) : String?
  attr = node[key]?
  attr.nil? ? nil : attr.val
end

describe "HTML5 Parsing" do
  describe "HTML5.parse basic functionality" do
    it "parses simple HTML" do
      html = "<html><head></head><body></body></html>"
      doc = HTML5.parse(html)
      doc.should_not be_nil
    end

    it "parses HTML with link elements" do
      html = <<-HTML
        <html>
          <head>
            <link rel="icon" href="/favicon.ico">
          </head>
        </html>
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='icon']")
      nodes.should_not be_empty
    end

    it "handles malformed HTML" do
      html = "<html><head><link rel=\"icon\" href=\"/favicon.ico\"></head>"
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='icon']")
      nodes.should_not be_empty
    end

    it "extracts href attribute from link element" do
      html = <<-HTML
        <link rel="icon" href="/favicon.ico">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='icon']")
      nodes.size.should eq(1)
      get_attr_val(nodes.first, "href").should eq("/favicon.ico")
    end

    it "extracts sizes attribute from link element" do
      html = <<-HTML
        <link rel="icon" href="/favicon.ico" sizes="32x32">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='icon']")
      nodes.size.should eq(1)
      get_attr_val(nodes.first, "sizes").should eq("32x32")
    end

    it "extracts type attribute from link element" do
      html = <<-HTML
        <link rel="icon" href="/favicon.ico" type="image/x-icon">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='icon']")
      nodes.size.should eq(1)
      get_attr_val(nodes.first, "type").should eq("image/x-icon")
    end
  end

  describe "CSS Selectors for favicon detection" do
    it "finds link with rel~='icon' (contains icon)" do
      html = <<-HTML
        <link rel="icon" href="/favicon.ico">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
    end

    it "finds link with rel='shortcut icon'" do
      html = <<-HTML
        <link rel="shortcut icon" href="/favicon.ico">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='shortcut icon']")
      nodes.should_not be_empty
    end

    it "finds link with rel='apple-touch-icon'" do
      html = <<-HTML
        <link rel="apple-touch-icon" href="/apple-touch-icon.png">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='apple-touch-icon']")
      nodes.should_not be_empty
    end

    it "finds link with rel='apple-touch-icon-precomposed'" do
      html = <<-HTML
        <link rel="apple-touch-icon-precomposed" href="/apple-touch-icon.png">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='apple-touch-icon-precomposed']")
      nodes.should_not be_empty
    end

    it "finds link with type='image/x-icon'" do
      html = <<-HTML
        <link type="image/x-icon" href="/favicon.ico">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[type='image/x-icon']")
      nodes.should_not be_empty
    end

    it "finds multiple favicon links" do
      html = <<-HTML
        <html>
          <head>
            <link rel="icon" href="/favicon.ico" sizes="16x16">
            <link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">
            <link rel="icon" type="image/png" href="/favicon-32x32.png" sizes="32x32">
          </head>
        </html>
        HTML
      doc = HTML5.parse(html)

      icon_nodes = doc.css("link[rel~='icon']")
      icon_nodes.size.should be >= 2

      apple_nodes = doc.css("link[rel='apple-touch-icon']")
      apple_nodes.size.should eq(1)
    end
  end

  describe "Manifest link detection" do
    it "finds manifest link" do
      html = <<-HTML
        <link rel="manifest" href="/manifest.json">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='manifest']")
      nodes.should_not be_empty
    end

    it "extracts manifest href" do
      html = <<-HTML
        <link rel="manifest" href="/site.webmanifest">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='manifest']")
      nodes.size.should eq(1)
      get_attr_val(nodes.first, "href").should eq("/site.webmanifest")
    end

    it "handles missing manifest link" do
      html = <<-HTML
        <html><head></head></html>
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel='manifest']")
      nodes.should be_empty
    end
  end

  describe "Complex HTML parsing" do
    it "parses full HTML document with multiple elements" do
      html = <<-HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Test Page</title>
          <link rel="icon" type="image/x-icon" href="/favicon.ico">
          <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
          <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
          <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
          <link rel="manifest" href="/site.webmanifest">
        </head>
        <body>
          <h1>Hello World</h1>
        </body>
        </html>
        HTML

      doc = HTML5.parse(html)

      icon_nodes = doc.css("link[rel~='icon']")
      icon_nodes.size.should be >= 3

      manifest_nodes = doc.css("link[rel='manifest']")
      manifest_nodes.size.should eq(1)
    end

    it "handles HTML with special characters" do
      html = <<-HTML
        <link rel="icon" href="/favicon.ico?param=value&other=test">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
      href = get_attr_val(nodes.first, "href")
      href.should_not be_nil
      href.as(String).includes?("/favicon.ico").should be_true
    end

    it "handles empty href attribute" do
      html = <<-HTML
        <link rel="icon" href="">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
      href = get_attr_val(nodes.first, "href")
      href.should eq("")
    end

    it "handles missing href attribute" do
      html = <<-HTML
        <link rel="icon">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
      href = get_attr_val(nodes.first, "href")
      href.should be_nil
    end
  end

  describe "Data URL handling" do
    it "parses link with data URL in href" do
      html = <<-HTML
        <link rel="icon" href="data:image/png;base64,iVBORw0KGgo=">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
      href = get_attr_val(nodes.first, "href")
      href.should_not be_nil
      href.as(String).starts_with?("data:").should be_true
    end
  end

  describe "URL scheme validation" do
    it "handles protocol-relative URLs" do
      html = <<-HTML
        <link rel="icon" href="//example.com/favicon.ico">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
      get_attr_val(nodes.first, "href").should eq("//example.com/favicon.ico")
    end

    it "handles absolute URLs" do
      html = <<-HTML
        <link rel="icon" href="https://cdn.example.com/favicon.ico">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
      get_attr_val(nodes.first, "href").should eq("https://cdn.example.com/favicon.ico")
    end

    it "handles relative URLs" do
      html = <<-HTML
        <link rel="icon" href="/assets/favicon.ico">
        HTML
      doc = HTML5.parse(html)
      nodes = doc.css("link[rel~='icon']")
      nodes.should_not be_empty
      get_attr_val(nodes.first, "href").should eq("/assets/favicon.ico")
    end
  end
end
