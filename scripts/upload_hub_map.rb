require 'json'
require 'aws-sdk-s3'
require_relative '../airtable'

# Set up a client that can upload files to Amazon S3 (a file hosting service)
s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

# Upload hub map json to S3
s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'hub_map.html',
  body: File.read('public/hub_map.html')
)
