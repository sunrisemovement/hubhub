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
while date <= Date.today
  0.upto(23).each do |i|
    name = "#{date}-#{i.to_s.rjust(2, '0')}.tsv"
    path = "#{PATH}/dt=#{date}"
    if File.exists?("#{LOG_DIR}/#{name}")
      tsv = File.read("#{LOG_DIR}/#{name}")
      logs += tsv.split("\n").map { |line| line.strip.split("\t") }
    else
      key = "#{path}/#{name}.gz"
      puts key
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
email_updates = Hash.new { |h,k| h[k] = 0 }
micro_updates = Hash.new { |h,k| h[k] = 0 }

logs_by_id = Hash.new { |h,k| h[k] = [] }

events = []

logs.each do |log|
  entry = log[-1]
  next unless entry.include?('INFO -')
  next unless hub_id = entry[/Hub (\w+)/, 1]

  logs_by_id[hub_id] << entry

  if entry.include?('Attempting login')
    next unless hub_name = entry[/Hub \w+ \(([^\)]+)\)/, 1]
    ids_to_hub_names[hub_id] ||= []
    unless ids_to_hub_names[hub_id].include?(hub_name)
      ids_to_hub_names[hub_id] << hub_name
    end
    login_attempts[hub_name] += 1
  else
    hub_name = (ids_to_hub_names[hub_id] || []).last
  end

  if entry.include?("Attempting login")
    events << { hub_id: hub_id, type: 'login-attempt', entry: entry, date: log[1], ip: log[5] }
  elsif entry.include?('Login successful')
    login_successes[hub_name] += 1
    events << { hub_id: hub_id, type: 'login-success', entry: entry, date: log[1], ip: log[5] }
  elsif entry.include?('Editing map info')
    map_info_edits[hub_name] += 1
    events << { hub_id: hub_id, type: 'map-edit', entry: entry, date: log[1], ip: log[5] }
  elsif entry.include?('Editing leader info')
    leader_edits[hub_name] += 1
    events << { hub_id: hub_id, type: 'leader-edit', entry: entry, date: log[1], ip: log[5] }
  elsif entry.include?('Updated hub email')
    email_updates[hub_name] += 1
    events << { hub_id: hub_id, type: 'email-edit', entry: entry, date: log[1], ip: log[5] }
  elsif entry.include?('Editing microsite info')
    micro_updates[hub_name] += 1
    events << { hub_id: hub_id, type: 'microsite-edit', entry: entry, date: log[1], ip: log[5] }
  end
end

events.each do |event|
  event[:hub_name] = (ids_to_hub_names[event[:hub_id]] || []).last
end

cols = [:hub_id, :hub_name, :type, :date, :ip]

require 'csv'
File.write("#{LOG_DIR}/events.csv", CSV.generate { |csv|
  csv << cols
  events.each do |ev|
    csv << ev.values_at(*cols)
  end
})

binding.pry

