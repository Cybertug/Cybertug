#!/usr/bin/env ruby
# Read-only App Store Connect audit for Simula Pro's subscription products.
require 'json'
require 'openssl'
require 'base64'
require 'net/http'
require 'uri'

%w[APPSTORE_API_KEY_ID APPSTORE_ISSUER_ID APPSTORE_API_PRIVATE_KEY].each do |name|
  abort "Missing #{name}" if ENV[name].to_s.empty?
end

def b64(data)
  Base64.urlsafe_encode64(data, padding: false)
end

now = Time.now.to_i
header = {alg: 'ES256', typ: 'JWT', kid: ENV.fetch('APPSTORE_API_KEY_ID')}
claims = {iss: ENV.fetch('APPSTORE_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1'}
prefix = [header, claims].map { |part| b64(JSON.generate(part)) }.join('.')
key = OpenSSL::PKey.read(ENV.fetch('APPSTORE_API_PRIVATE_KEY'))
der = key.sign(OpenSSL::Digest.new('SHA256'), prefix)
signature = OpenSSL::ASN1.decode(der).value.map { |part| [part.value.to_s(16).rjust(64, '0')].pack('H*') }.join
token = "#{prefix}.#{b64(signature)}"

def get_json(path, token)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{token}"
  request['Accept'] = 'application/json'
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 35) { |http| http.request(request) }
  unless response.code == '200'
    errors = (JSON.parse(response.body)['errors'] rescue [])
    abort "Apple API #{uri.path}: HTTP #{response.code}, #{Array(errors).map { |e| e['code'] }.join(', ')}"
  end
  JSON.parse(response.body)
end

app_id = '6823960478'
groups = get_json("/v1/apps/#{app_id}/subscriptionGroups?limit=200", token).fetch('data')
puts "Subscription groups: #{groups.length}"
found = []
groups.each do |group|
  group_id = group.fetch('id')
  puts "Group: #{group.dig('attributes', 'referenceName')} (#{group_id})"
  products = get_json("/v1/subscriptionGroups/#{group_id}/subscriptions?limit=200", token).fetch('data')
  products.each do |product|
    attrs = product.fetch('attributes')
    product_id = attrs.fetch('productId')
    found << product_id
    prices = get_json("/v1/subscriptions/#{product.fetch('id')}/prices?filter%5Bterritory%5D=USA&limit=200", token).fetch('data')
    puts "Product: #{product_id}; state=#{attrs['state']}; period=#{attrs['subscriptionPeriod']}; USA price records=#{prices.length}"
  end
end
expected = %w[com.simulapro.access.monthly com.simulapro.access.yearly]
puts "Expected product IDs present: #{(expected - found).empty?}"

