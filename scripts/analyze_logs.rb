require 'json'
require 'aws-sdk-s3'
require 'pry'
require 'zlib'
require_relative '../environment'

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

BUCKET = ENV['LOG_BUCKET']
PATH = ENV['LOG_PATH']

LOG_DIR = "#{__dir__}/../logs"

date = Date.new(2020, 2, 24)

logs = []
while date < Date.today
  0.upto(23).each do |i|
    name = "#{date}-#{i.to_s.rjust(2, '0')}.tsv"
    path = "#{PATH}/dt=#{date}"
    if File.exists?("#{LOG_DIR}/#{name}")
      tsv = File.read("#{LOG_DIR}/#{name}")
      logs += tsv.split("\n").map { |line| line.strip.split("\t") }
    else
      key = "#{path}/#{name}.gz"
      obj = s3.get_object(bucket: BUCKET, key: key) rescue next
      str = obj.body.string
      tsv = Zlib::GzipReader.new(StringIO.new(str)).read
      File.write("#{LOG_DIR}/#{name}", tsv)
      logs += tsv.split("\n").map { |line| line.strip.split("\t") }
    end
  end
  date = date + 1
end

ids_to_hub_names = {}
login_attempts = Hash.new { |h,k| h[k] = 0 }
login_successes = Hash.new { |h,k| h[k] = 0 }
map_info_edits = Hash.new { |h,k| h[k] = 0 }
leader_edits = Hash.new { |h,k| h[k] = 0 }

logs.each do |log|
  entry = log[-1]
  next unless entry.include?('INFO -')
  next unless hub_id = entry[/Hub (\w+)/, 1]

  if entry.include?('Attempting login')
    next unless hub_name = entry[/Hub \w+ \(([^\)]+)\)/, 1]
    ids_to_hub_names[hub_id] = hub_name
    login_attempts[hub_name] += 1
  else
    hub_name = ids_to_hub_names[hub_id]
  end

  if entry.include?('Login successful')
    login_successes[hub_name] += 1
  elsif entry.include?('Editing map info')
    map_info_edits[hub_name] += 1
  elsif entry.include?('Editing leader info')
    leader_edits[hub_name] += 1
  end
end

binding.pry

