#!/usr/bin/env ruby
# Update only the primary App Store name for the existing application.
require 'json'
require 'openssl'
require 'base64'
require 'net/http'
require 'uri'

API = 'https://api.appstoreconnect.apple.com'
APP_ID = '6823960478'
BUNDLE_ID = 'com.simulapro.psychologylaw'
GROUP_NAME = 'SimulaPro Internal'
EXPECTED_BUILD = '6'

%w[APPSTORE_API_KEY_ID APPSTORE_ISSUER_ID APPSTORE_API_PRIVATE_KEY].each do |name|
  abort "Missing credential setting: #{name}" if ENV[name].to_s.empty?
end

def base64url(input)
  Base64.urlsafe_encode64(input, padding: false)
end

now = Time.now.to_i
head = {alg: 'ES256', typ: 'JWT', kid: ENV.fetch('APPSTORE_API_KEY_ID')}
claims = {iss: ENV.fetch('APPSTORE_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1'}
prefix = [head, claims].map { |part| base64url(JSON.generate(part)) }.join('.')
private_key = OpenSSL::PKey.read(ENV.fetch('APPSTORE_API_PRIVATE_KEY'))
der = private_key.sign(OpenSSL::Digest.new('SHA256'), prefix)
asn1 = OpenSSL::ASN1.decode(der)
raw_sig = asn1.value.map { |item| [item.value.to_s(16).rjust(64, '0')].pack('H*') }.join
abort 'JWT signing failed' unless raw_sig.bytesize == 64
TOKEN = "#{prefix}.#{base64url(raw_sig)}"

def call_api(method, path, body=nil)
  uri = URI("#{API}#{path}")
  req_class = {'GET'=>Net::HTTP::Get, 'POST'=>Net::HTTP::Post, 'PATCH'=>Net::HTTP::Patch}.fetch(method)
  req = req_class.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Accept'] = 'application/json'
  req['Content-Type'] = 'application/json' if body
  req.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 35) { |h| h.request(req) }
  unless [200,201,204].include?(response.code.to_i)
    errors = (JSON.parse(response.body.to_s)['errors'] rescue [])
    codes = Array(errors).map { |e| e['code'].to_s.gsub(/[^A-Za-z0-9_-]/, '') }.join(', ')
    details = Array(errors).map { |e| e['detail'].to_s.gsub(/[\r\n]/, ' ').gsub(/[^\x20-\x7e]/, '') }.join('; ')
    abort "Apple API #{method} #{uri.path}: HTTP #{response.code}, codes #{codes[0,100]}, detail #{details[0,350]}"
  end
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

app = call_api('GET', "/v1/apps/#{APP_ID}")['data']
abort 'Wrong app bundle ID' unless app.dig('attributes','bundleId') == BUNDLE_ID
locale = app.dig('attributes','primaryLocale')
abort 'App has no primary locale' if locale.to_s.empty?
infos = call_api('GET', "/v1/apps/#{APP_ID}/appInfos?limit=200")['data']
abort 'No app info found' if infos.empty?
targets = infos.flat_map do |info|
  call_api('GET', "/v1/appInfos/#{info.fetch('id')}/appInfoLocalizations?limit=200")['data']
end.select { |loc| loc.dig('attributes','locale') == locale }
abort "Expected one primary localization, found #{targets.size}" unless targets.size == 1
target = targets.first
if target.dig('attributes','name') == 'Simula Pro'
  puts 'SUCCESS: Existing app primary name is already Simula Pro.'
  exit 0
end
puts "Current primary name: #{target.dig('attributes','name')}"
call_api('PATCH', "/v1/appInfoLocalizations/#{target.fetch('id')}", {
  data: {type: 'appInfoLocalizations', id: target.fetch('id'), attributes: {name: 'Simula Pro'}}
})
updated = call_api('GET', "/v1/appInfoLocalizations/#{target.fetch('id')}")['data']
abort 'Name update did not persist' unless updated.dig('attributes','name') == 'Simula Pro'
abort 'App identity changed unexpectedly' unless call_api('GET', "/v1/apps/#{APP_ID}")['data'].dig('attributes','bundleId') == BUNDLE_ID
puts "SUCCESS: Existing app primary name is Simula Pro (#{locale}); bundle ID retained."
