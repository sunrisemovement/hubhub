require 'time'
require 'json'

def ma_response
  JSON.parse(`curl -d "message=MA" -X POST hubhub-staging.herokuapp.com/sms`)['message']
rescue
  nil
end

responses = []
dts = []
100.times do |s|
  puts s

  t1 = Time.now
  threads = 25.times.map { sleep(0.01); Thread.new { ma_response } }
  responses += threads.map { |t| t.join.value }

  t2 = Time.now

  dt = t2 - t1
  dts << dt

  if dt < 1
    sleep(1 - dt)
  end

end

puts responses.size
puts responses.uniq.size
puts responses.compact.size
puts dts
