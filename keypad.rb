require 'securerandom'
require_relative 'cache'

# Helper class to store and test temporary secret keys for link-based login.
class Keypad
  TIMEOUT = 10 * 60 # 10 minute timeout

  class << self
    # Generated keys are specific to hubs and expire after 10 minutes
    # (can be configured to last longer)
    def generate_key(hub, metadata=nil, timeout=nil)
      # Use `SecureRandom.urlsafe_base64` to generate the key
      SecureRandom.urlsafe_base64(32).tap do |key|
        timeout ||= TIMEOUT
        value = { hub_id: hub.id, metadata: metadata, expires_at: Time.now + timeout }
        CACHE.set(key, value, timeout)
      end
    end

    def enter_key(key)
      return unless value = CACHE.get(key)
      CACHE.delete(key)
      return unless time = value[:expires_at]
      return unless time >= Time.now
      value
    end
  end
end
