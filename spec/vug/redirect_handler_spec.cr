require "../spec_helper"
require "../../src/vug/redirect_handler"
require "../../src/vug/config"

class TestRedirectHandler < Vug::RedirectHandler
  def decide(original : String, redirect_url : String, redirect_count : Int32) : Vug::FetchAction::Base
    Vug::FetchAction::Deny.new(reason: "test")
  end
end

describe Vug::RedirectHandler do
  it "is abstract and responds to decide" do
    handler = TestRedirectHandler.new(Vug::Config.default)
    result = handler.decide("a", "b", 0)
    result.is_a?(Vug::FetchAction::Deny).should be_true
  end
end
