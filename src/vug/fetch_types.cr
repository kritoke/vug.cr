module Vug
  module FetchAction
    abstract class Base
    end

    class Follow < Base
      property location : String

      def initialize(location : String)
        @location = location
      end
    end

    class Deny < Base
      property reason : String

      def initialize(reason : String)
        @reason = reason
      end
    end
  end

  class FetchSuccess
    property fetched_url : String
    property path : String?
    property content_type : String?
    property status_code : Int32
    property width : Int32?
    property height : Int32?

    def initialize(fetched_url : String = "", path : String? = nil, content_type : String? = nil, status_code : Int32 = 0, width : Int32? = nil, height : Int32? = nil)
      @fetched_url = fetched_url
      @path = path
      @content_type = content_type
      @status_code = status_code
      @width = width
      @height = height
    end
  end

  class FetchError
    property target_url : String
    property error_type : Symbol
    property message : String

    def initialize(target_url : String = "", error_type : Symbol = :unknown, message : String = "")
      @target_url = target_url
      @error_type = error_type
      @message = message
    end
  end
end
