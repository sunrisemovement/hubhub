ENV['APP_ENV'] = 'test'

require_relative '../airtable'
require_relative '../app'
require 'minitest/autorun'
require 'minitest/pride'
require 'capybara/minitest'
require 'capybara/minitest/spec'
require 'securerandom'
require 'erb'
require 'pry'
require 'rb-readline'
require 'timecop'

class Minitest::Test
  def log_in_as(hub)
    visit '/'
    select hub, from: 'hub'
    click_button 'Send Magic Link'
    email = Emailer.last_email
    magic_link = email[:body][/https?:\/\/[\S]+/]
    visit magic_link
  end

  def inline_map_json
    el = find('#map-entry-json')
    json = JSON.parse(JSON.parse(el[:'data-map-data']))
    json['map_data'][0]
  end

  def setup
    Hub.base_key = 'foo'
    Leader.base_key = 'foo'
    Airrecord.api_key = 'foo'

    Hub.client.connection = Faraday.new { |builder|
      builder.adapter :test, Faraday::Adapter::Test::Stubs.new
    }
    Leader.client.connection = Faraday.new { |builder|
      builder.adapter :test, Faraday::Adapter::Test::Stubs.new
    }
  end

  def hub_stubs
    Hub.client.connection.app.stubs
  end

  def ldr_stubs
    Leader.client.connection.app.stubs
  end

  def hub_url
    "/v0/#{ERB::Util.u(Hub.base_key)}/#{ERB::Util.u(Hub.table_name)}"
  end

  def ldr_url
    "/v0/#{ERB::Util.u(Leader.base_key)}/#{ERB::Util.u(Leader.table_name)}"
  end

  def stub_hubs(records, status: 200, headers: {}, offset: nil)
    body = {
      records: records.map { |record|
        {
          id: record["id"] || SecureRandom.hex(16),
          fields: record,
          createdTime: Time.now,
        }
      },
      offset: offset,
    }

    hub_stubs.get(hub_url) do |env|
      [status, headers, body.to_json]
    end

    body[:records].each do |record|
      hub_stubs.get("#{hub_url}/#{record[:id]}") do
        [status, headers, record.to_json]
      end
    end
  end

  def stub_leaders(records, status: 200, headers: {}, offset: nil)
    body = {
      records: records.map { |record|
        {
          id: record["id"] || SecureRandom.hex(16),
          fields: record,
          createdTime: Time.now,
        }
      },
      offset: offset,
    }

    ldr_stubs.get(ldr_url) do |env|
      [status, headers, body.to_json]
    end

    body[:records].each do |record|
      ldr_stubs.get("#{ldr_url}/#{record[:id]}") do
        [status, headers, record.to_json]
      end
    end
  end
end

class CapybaraTest < Minitest::Test
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  def teardown
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end

Capybara.app = Hubhub
