module Vug
  class DNSRevalidator
    def initialize(@config : Config); end

    # Compare old_ips and new_ips and decide whether a DNS re-resolution warrants a retry
    def should_revalidate?(old_ips : Array(String), new_ips : Array(String)) : Bool
      old_ips.sort != new_ips.sort
    end
  end
end
