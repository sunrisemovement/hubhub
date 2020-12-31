require 'dalli'

# Use Memcached for persistent cache storage so entries don't depend on which
# specific dyno serves the request.
CACHE = if ENV['MEMCACHEDCLOUD_SERVERS']
  Dalli::Client.new(
    ENV['MEMCACHEDCLOUD_SERVERS'].split(','),
    username: ENV['MEMCACHEDCLOUD_USERNAME'],
    password: ENV['MEMCACHEDCLOUD_PASSWORD']
  )
else
  Dalli::Client.new
end
