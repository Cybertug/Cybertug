#!/usr/bin/env ruby
# One-time App Store Connect access adjustment: no secrets or user details are logged.
require 'json'
require 'openssl'
require 'base64'
require 'net/http'
require 'uri'

API = 'https://api.appstoreconnect.apple.com'
APP_ID = '6823960478'
BUNDLE_ID = 'com.simulapro.psychologylaw'
GROUP_NAME = 'SimulaPro Internal'

%w[APPSTORE_API_KEY_ID APPSTORE_ISSUER_ID APPSTORE_API_PRIVATE_KEY].each do |key|
  abort "Missing secret #{key}" if ENV[key].to_s.empty?
end

def base64url(input)
  Base64.urlsafe_encode64(input, padding: false)
end

now = Time.now.to_i
header = {alg: 'ES256', typ: 'JWT', kid: ENV.fetch('APPSTORE_API_KEY_ID')}
claims = {iss: ENV.fetch('APPSTORE_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1'}
prefix = [header, claims].map { |x| base64url(JSON.generate(x)) }.join('.')
key = OpenSSL::PKey.read(ENV.fetch('APPSTORE_API_PRIVATE_KEY'))
der = key.sign(OpenSSL::Digest.new('SHA256'), prefix)
seq = OpenSSL::ASN1.decode(der)
raw_signature = seq.value.map { |part| [part.value.to_s(16).rjust(64, '0')].pack('H*') }.join
abort 'Invalid JWT signing key format' unless raw_signature.bytesize == 64
TOKEN = "#{prefix}.#{base64url(raw_signature)}"

def request(method, path, body = nil, accepted: [200, 201, 204])
  uri = URI.parse("#{API}#{path}")
  klass = {'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'PATCH' => Net::HTTP::Patch}.fetch(method)
  req = klass.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Accept'] = 'application/json'
  req['Content-Type'] = 'application/json' if body
  req.body = JSON.generate(body) if body
  resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |http| http.request(req) }
  unless accepted.include?(resp.code.to_i)
    parsed = JSON.parse(resp.body.to_s) rescue {}
    names = Array(parsed['errors']).map { |e| e['code'] || e['title'] }.compact.map { |x| x.to_s.gsub(/[^A-Za-z0-9_\- ]/, '') }
    abort "Apple API #{method} #{uri.path} returned HTTP #{resp.code} (#{names.join(', ')[0,160]})"
  end
  return {} if resp.body.to_s.empty?
  JSON.parse(resp.body)
end

# Check app identity before granting any additional access.
app = request('GET', "/v1/apps/#{APP_ID}")['data']
abort 'Unexpected app bundle ID; refusing access change' unless app.dig('attributes', 'bundleId') == BUNDLE_ID

users = request('GET', '/v1/users?limit=200')['data']
matches = users.select do |u|
  a = u['attributes'] || {}
  a['firstName'].to_s.casecmp('Aixa').zero? && a['lastName'].to_s.casecmp('Fretts').zero?
end
abort "Expected exactly one Aixa Fretts user; found #{matches.size}" unless matches.size == 1
user = matches.first
roles = Array(user.dig('attributes', 'roles'))
if roles.include?('MARKETING') || roles.any? { |x| %w[ADMIN APP_MANAGER DEVELOPER ACCOUNT_HOLDER].include?(x) }
  puts 'Aixa already has a role eligible for internal TestFlight.'
else
  new_roles = (roles - ['SALES'] + ['MARKETING']).uniq
  abort 'User has unexpected access roles' unless roles.include?('SALES')
  request('PATCH', "/v1/users/#{user.fetch('id')}", {
    data: {type: 'users', id: user.fetch('id'), attributes: {roles: new_roles}}
  })
  puts 'Aixa role updated to Marketing (Sales replaced).'
end

# This beta group is the internal group for the specified application only.
groups = request('GET', '/v1/betaGroups?limit=200')['data']
matching = groups.select do |g|
  g.dig('attributes', 'name') == GROUP_NAME &&
    g.dig('attributes', 'isInternalGroup') == true &&
    g.dig('relationships', 'app', 'data', 'id') == APP_ID
end
abort "Internal group not uniquely identified (#{matching.size} matches)" unless matching.size == 1
group_id = matching.first.fetch('id')

# Ensure the latest usable build belongs to this internal group.
builds = request('GET', "/v1/builds?filter%5Bapp%5D=#{APP_ID}&limit=200")['data']
usable = builds.select { |b| b.dig('attributes', 'processingState') == 'VALID' }
latest = usable.max_by { |b| b.dig('attributes', 'version').to_s.to_i }
abort 'No processed iOS build available' unless latest
existing_builds = request('GET', "/v1/betaGroups/#{group_id}/builds?limit=200")['data']
unless existing_builds.any? { |b| b['id'] == latest['id'] }
  request('POST', "/v1/betaGroups/#{group_id}/relationships/builds", {
    data: [{type: 'builds', id: latest.fetch('id')}]
  })
  puts "Latest processed Build #{latest.dig('attributes', 'version')} added to SimulaPro Internal."
else
  puts "Latest Build #{latest.dig('attributes', 'version')} was already available internally."
end

# Use Apple's existing tester record if present; don't delete external testing access.
user_email = user.dig('attributes', 'username').to_s.downcase
abort 'Aixa account has no Apple Account email' if user_email.empty?
testers = request('GET', '/v1/betaTesters?limit=200')['data']
matched_testers = testers.select { |t| t.dig('attributes', 'email').to_s.downcase == user_email }
abort "Ambiguous beta tester account (#{matched_testers.size} matches)" if matched_testers.size > 1
if matched_testers.empty?
  created = request('POST', '/v1/betaTesters', {
    data: {
      type: 'betaTesters',
      attributes: {email: user_email, firstName: user.dig('attributes', 'firstName'), lastName: user.dig('attributes', 'lastName')},
      relationships: {betaGroups: {data: [{type: 'betaGroups', id: group_id}]}}
    }
  })
  tester_id = created.fetch('data').fetch('id')
  puts 'Aixa internal TestFlight tester created.'
else
  tester_id = matched_testers.first.fetch('id')
  current = request('GET', "/v1/betaGroups/#{group_id}/betaTesters?limit=200")['data']
  unless current.any? { |t| t['id'] == tester_id }
    request('POST', "/v1/betaGroups/#{group_id}/relationships/betaTesters", {
      data: [{type: 'betaTesters', id: tester_id}]
    })
    puts 'Aixa added to SimulaPro Internal tester group.'
  else
    puts 'Aixa was already in SimulaPro Internal tester group.'
  end
end

# Verify the permanent state, not just the success of POST requests.
updated = request('GET', "/v1/users/#{user.fetch('id')}")['data']
abort 'Aixa role not yet activated' unless Array(updated.dig('attributes', 'roles')).any? { |r| %w[MARKETING ADMIN APP_MANAGER DEVELOPER ACCOUNT_HOLDER].include?(r) }
verified = request('GET', "/v1/betaGroups/#{group_id}/betaTesters?limit=200")['data']
abort 'Aixa not found in internal tester group' unless verified.any? { |t| t['id'] == tester_id }
puts 'SUCCESS: Aixa has eligible role and is in SimulaPro Internal with processed build.'