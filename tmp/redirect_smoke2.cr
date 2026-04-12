require "../src/vug/redirect_handler_default"
require "../src/vug/fetch_types"
require "../src/vug/config"

config = Vug::Config.new
handler = Vug::RedirectHandler::Default.new(config)

action1 = handler.decide("https://a/1", "http://a/2", 0)
action2 = handler.decide("https://a/1", "http://a/2", 1)
action3 = handler.decide("http://a/1", "http://b/2", 0)
action4 = handler.decide("http://a", "http://a", 0)

puts action1.class
puts action2.is_a?(Vug::FetchAction::Deny)
puts action3.is_a?(Vug::FetchAction::Follow)
puts action4.is_a?(Vug::FetchAction::Deny)
