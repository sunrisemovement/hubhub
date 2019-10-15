require_relative '../airtable'
require 'minitest/autorun'
require 'minitest/pride'
require 'securerandom'
require 'erb'
require 'pry'

class Minitest::Test
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

  def clear_stubs
    hub_stubs.instance_variable_set(:@stack, {})
    ldr_stubs.instance_variable_set(:@stack, {})
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
    }.to_json

    hub_stubs.get(hub_url) do |env|
      [status, headers, body]
    end
  end

  def stub_leaders(records, status: 200, headers: {}, offset: nil, clear: true)
    body = {
      records: records.map { |record|
        {
          id: record["id"] || SecureRandom.hex(16),
          fields: record,
          createdTime: Time.now,
        }
      },
      offset: offset,
    }.to_json

    ldr_stubs.get(ldr_url) do |env|
      [status, headers, body]
    end
  end
end
