module Vug
  module DNSRevalidator
    # Compare old_ips and new_ips and decide whether DNS has changed (possible rebinding)
    def self.should_revalidate?(old_ips : Array(String), new_ips : Array(String)) : Bool
      old_ips.sort != new_ips.sort
    end
  end
end
