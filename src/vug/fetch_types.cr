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
end
