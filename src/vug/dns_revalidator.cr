module Vug
  class DNSRevalidator
    def initialize(@config : Config); end

    # Compare old_ips and new_ips and decide whether a DNS re-resolution warrants a retry
    def should_revalidate?(old_ips : Array(String), new_ips : Array(String)) : Bool
      # Default conservative behaviour: revalidate if IP sets differ
      old_set = old_ips.to_set
      new_set = new_ips.to_set
      old_set != new_set
    end
  end
end
