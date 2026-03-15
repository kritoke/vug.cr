module Vug
  record Result,
    url : String?,
    local_path : String?,
    content_type : String?,
    bytes : Bytes?,
    error : String? do
    def success? : Bool
      !local_path.nil? && error.nil?
    end

    def redirect? : Bool
      local_path.nil? && error.nil? && !url.nil?
    end

    def failure? : Bool
      !error.nil?
    end
  end

  def self.success(url : String, local_path : String, content_type : String? = nil, bytes : Bytes? = nil) : Result
    Result.new(url: url, local_path: local_path, content_type: content_type, bytes: bytes, error: nil)
  end

  def self.failure(error : String, url : String? = nil) : Result
    Result.new(url: url, local_path: nil, content_type: nil, bytes: nil, error: error)
  end
end
