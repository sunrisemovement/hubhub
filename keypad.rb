require 'securerandom'

# Helper class to store and test temporary secret keys for link-based login.
class Keypad
  @store = {}

  TIMEOUT = 10 * 60 # 10 minute timeout

  class << self
    attr_reader :store

    # Generated keys are specific to hubs and expire after 10 minutes
    def generate_key(hub, metadata=nil)
      old_keys = @store.keys.select{ |k| @store[k][:hub_id] == hub.id }
      old_keys.each do |key|
        @store.delete(key)
      end
      # Use `SecureRandom.urlsafe_base64` to generate the key
      SecureRandom.urlsafe_base64(32).tap do |key|
        @store[key] = { hub_id: hub.id, time: Time.now, metadata: metadata }
      end
    end

    def enter_key(key)
      # First remove any expired keys
      @store.each { |k, o| @store.delete(k) if Time.now - o[:time] > TIMEOUT }
      # Then simultaneously fetch and delete the specific key (returning nil if
      # it does not exist)
      @store.delete(key)
    end
  end
end
