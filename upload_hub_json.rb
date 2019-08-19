require 'json'
require 'aws-sdk-s3'
require_relative 'airtable'

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'hubs.json',
  body: JSON.dump({
    updated_at: Time.now.to_s,
    map_data: Hub.map_json
  })
)
