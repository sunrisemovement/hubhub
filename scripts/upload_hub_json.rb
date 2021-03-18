require 'json'
require 'aws-sdk-s3'
require 'httparty'
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
  key: 'hubs.json',
  body: JSON.dump({
    updated_at: Time.now.to_s,
    map_data: Hub.map_json
  })
)

if token = ENV['MICROSITE_GITHUB_ACCESS_TOKEN']
  # Deploy microsites
  HTTParty.post(
    "https://api.github.com/repos/sunrisemovement/smvmt-microsite/dispatches",
    body: {
      event_type: 'deploy',
    },
    headers: {
      "Authorization" => "token #{token}"
    }
  )
end
