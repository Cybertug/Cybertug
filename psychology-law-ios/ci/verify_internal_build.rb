#!/usr/bin/env ruby
# Add a new iOS build to the EXISTING internal testing group using protected Apple API credentials.
# No new app, group, user, role, or provisioning profiles are created.
require 'json'
require 'openssl'
require 'base64'
require 'net/http'
require 'uri'

API = 'https://api.appstoreconnect.apple.com'
APP_ID = '6823960478'
BUNDLE_ID = 'com.simulapro.psychologylaw'
GROUP_NAME = 'SimulaPro Internal'
EXPECTED_BUILD = ENV.fetch('RELEASE_BUILD_NUMBER')

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
groups = call_api('GET', '/v1/betaGroups?limit=200')['data']
matches = groups.select { |g| g.dig('attributes','name') == GROUP_NAME && g.dig('attributes','isInternalGroup') == true }
abort "Expected one internal group; found #{matches.size}" unless matches.size == 1
group_id = matches.first.fetch('id')
owning_app = call_api('GET', "/v1/betaGroups/#{group_id}/app")['data']
abort 'Unexpected owning app' unless owning_app && owning_app['id'] == APP_ID

builds_path = "/v1/builds?filter%5Bapp%5D=#{APP_ID}&limit=200"
target = nil
# The upload can be complete while Apple is still processing the IPA.
16.times do |attempt|
  builds = call_api('GET', builds_path)['data']
  candidates = builds.select { |b| b.dig('attributes','version').to_s == EXPECTED_BUILD }
  target = candidates.find { |b| b.dig('attributes','processingState') == 'VALID' }
  break if target
  status = candidates.map { |b| b.dig('attributes','processingState') }.uniq.join('/')
  puts "Build #{EXPECTED_BUILD} not processed yet (#{status.empty? ? 'not listed' : status}); waiting (#{attempt+1}/16)."
  sleep 20 if attempt < 15
end
abort "Build #{EXPECTED_BUILD} is not VALID yet; retry once Apple finishes processing" unless target

details = call_api('GET', "/v1/builds/#{target.fetch('id')}/buildBetaDetail")['data']
if details.dig('attributes','internalBuildState') == 'MISSING_EXPORT_COMPLIANCE'
  encryption_flag = target.dig('attributes','usesNonExemptEncryption')
  abort 'Build reports non-exempt encryption; cannot declare exemption automatically' if encryption_flag == true
  # App contains original SwiftUI educational practice content, no custom cryptography.
  # Same "none of the algorithms" exemption selected for the original build.
  call_api('PATCH', "/v1/builds/#{target.fetch('id')}", {
    data: {type: 'builds', id: target.fetch('id'), attributes: {usesNonExemptEncryption: false}}
  })
  puts "Saved export-compliance exemption for Build #{EXPECTED_BUILD}."
  details = call_api('GET', "/v1/builds/#{target.fetch('id')}/buildBetaDetail")['data']
end
group_data = call_api('GET', "/v1/betaGroups/#{group_id}")['data']
puts "Build #{EXPECTED_BUILD}: audience=#{target.dig('attributes','buildAudienceType')}, processing=#{target.dig('attributes','processingState')}, internalBetaState=#{details.dig('attributes','internalBuildState')}"
puts "Internal group automatic distribution=#{group_data.dig('attributes','hasAccessToAllBuilds')}"
existing = call_api('GET', "/v1/betaGroups/#{group_id}/builds?limit=200")['data']
puts "Internal group linked builds=#{existing.map { |b| b.dig('attributes','version') }.join(', ')}"
if group_data.dig('attributes','hasAccessToAllBuilds') == true
  puts 'Automatic internal distribution is enabled; waiting for Apple to assign the build.'
  18.times do |attempt|
    current = call_api('GET', "/v1/betaGroups/#{group_id}/builds?limit=200")['data']
    break if current.any? { |b| b['id'] == target.fetch('id') }
    state = call_api('GET', "/v1/builds/#{target.fetch('id')}/buildBetaDetail")['data'].dig('attributes','internalBuildState')
    puts "Build #{EXPECTED_BUILD} internal state=#{state}; assignment pending #{attempt+1}/18"
    sleep 10 if attempt < 17
  end
  current = call_api('GET', "/v1/betaGroups/#{group_id}/builds?limit=200")['data']
  abort "Apple has not made Build #{EXPECTED_BUILD} available to automatic group yet" unless current.any? { |b| b['id'] == target.fetch('id') }
  testers = call_api('GET', "/v1/betaGroups/#{group_id}/betaTesters?limit=200")['data']
  names = testers.map { |t| t.dig('attributes','firstName').to_s.strip.downcase }
  abort 'Luciano or Aixa missing from internal tester group' unless %w[luciano aixa].all? { |name| names.include?(name) }
  state = call_api('GET', "/v1/builds/#{target.fetch('id')}/buildBetaDetail")['data'].dig('attributes','internalBuildState')
  puts "SUCCESS: iOS Build #{EXPECTED_BUILD} available in SimulaPro Internal for Luciano and Aixa (#{testers.length} testers, state=#{state})."
  exit 0
end
unless existing.any? { |b| b['id'] == target.fetch('id') }
  call_api('POST', "/v1/betaGroups/#{group_id}/relationships/builds", {
    data: [{type: 'builds', id: target.fetch('id')}]
  })
  puts "Build #{EXPECTED_BUILD} linked to internal group."
else
  puts "Build #{EXPECTED_BUILD} was already in the internal group."
end

verify = call_api('GET', "/v1/betaGroups/#{group_id}/builds?limit=200")['data']
abort 'Verification failed: build not in group' unless verify.any? { |b| b['id'] == target['id'] }
testers = call_api('GET', "/v1/betaGroups/#{group_id}/betaTesters?limit=200")['data']
names = testers.map { |t| t.dig('attributes','firstName').to_s.strip.downcase }
abort 'Luciano or Aixa missing from internal tester group' unless %w[luciano aixa].all? { |name| names.include?(name) }
puts "SUCCESS: iOS version 1.0.0 Build #{EXPECTED_BUILD} is available in SimulaPro Internal for Luciano and Aixa (#{testers.length} internal testers)."

