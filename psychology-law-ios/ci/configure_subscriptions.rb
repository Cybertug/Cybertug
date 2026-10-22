#!/usr/bin/env ruby
# Idempotent setup of Simula Pro auto-renewable subscriptions in App Store Connect.
require 'json'
require 'openssl'
require 'base64'
require 'net/http'
require 'uri'

%w[APPSTORE_API_KEY_ID APPSTORE_ISSUER_ID APPSTORE_API_PRIVATE_KEY].each do |name|
  abort "Missing #{name}" if ENV[name].to_s.empty?
end

def b64(data) = Base64.urlsafe_encode64(data, padding: false)
now = Time.now.to_i
header = {alg: 'ES256', typ: 'JWT', kid: ENV.fetch('APPSTORE_API_KEY_ID')}
claims = {iss: ENV.fetch('APPSTORE_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1'}
prefix = [header, claims].map { |part| b64(JSON.generate(part)) }.join('.')
key = OpenSSL::PKey.read(ENV.fetch('APPSTORE_API_PRIVATE_KEY'))
der = key.sign(OpenSSL::Digest.new('SHA256'), prefix)
signature = OpenSSL::ASN1.decode(der).value.map { |part| [part.value.to_s(16).rjust(64, '0')].pack('H*') }.join
TOKEN = "#{prefix}.#{b64(signature)}"

def api(method, path, body=nil)
  uri = path.start_with?('https://') ? URI(path) : URI("https://api.appstoreconnect.apple.com#{path}")
  request = {'GET'=>Net::HTTP::Get, 'POST'=>Net::HTTP::Post}.fetch(method).new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Accept'] = 'application/json'
  if body
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 35) { |http| http.request(request) }
  unless [200, 201].include?(response.code.to_i)
    errors = (JSON.parse(response.body)['errors'] rescue [])
    detail = Array(errors).map { |e| "#{e['code']}: #{e['detail']}" }.join('; ')
    abort "Apple API #{method} #{uri.path}: HTTP #{response.code}: #{detail[0, 700]}"
  end
  JSON.parse(response.body)
end

def list(path)
  result = []
  while path
    page = api('GET', path)
    result.concat(page.fetch('data'))
    path = page.dig('links', 'next')
  end
  result
end

def create(type, path, attributes, relationships)
  api('POST', path, {data: {type: type, attributes: attributes, relationships: relationships}}).fetch('data')
end

app_id = '6823960478'
groups = list("/v1/apps/#{app_id}/subscriptionGroups?limit=200")
group = groups.find { |item| item.dig('attributes', 'referenceName') == 'Simula Pro Access' }
abort "Unexpected existing subscription groups: #{groups.map { |g| g.dig('attributes', 'referenceName') }.join(', ')}" if !groups.empty? && !group
unless group
  group = create('subscriptionGroups', '/v1/subscriptionGroups',
                 {referenceName: 'Simula Pro Access'},
                 {app: {data: {type: 'apps', id: app_id}}})
  puts "Created subscription group #{group.fetch('id')}"
end
group_id = group.fetch('id')

versions = list("/v1/subscriptionGroups/#{group_id}/versions?limit=200")
if versions.any?
  version = versions.find { |v| %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW].include?(v.dig('attributes', 'state')) } || versions.first
  version_id = version.fetch('id')
  existing = list("/v1/subscriptionGroupVersions/#{version_id}/localizations?limit=200")
  unless existing.any? { |x| x.dig('attributes', 'locale') == 'en-US' }
    create('subscriptionGroupLocalizations', '/v2/subscriptionGroupLocalizations',
           {name: 'Simula Pro Access', locale: 'en-US'},
           {version: {data: {type: 'subscriptionGroupVersions', id: version_id}}})
    puts 'Created en-US subscription group localization'
  end
else
  puts 'No subscription group version returned; group localization needs review.'
end

products = list("/v1/subscriptionGroups/#{group_id}/subscriptions?limit=200")
plans = [
  {id: 'com.simulapro.access.monthly', name: 'Simula Pro Access Monthly', period: 'ONE_MONTH', price: '9.99', description: 'All Simula Pro exam simulators for one month.'},
  {id: 'com.simulapro.access.yearly', name: 'Simula Pro Access Yearly', period: 'ONE_YEAR', price: '79.99', description: 'All Simula Pro exam simulators for one year.'}
]
plans.each do |plan|
  product = products.find { |p| p.dig('attributes', 'productId') == plan.fetch(:id) }
  unless product
    product = create('subscriptions', '/v1/subscriptions',
                     {name: plan.fetch(:name), productId: plan.fetch(:id), subscriptionPeriod: plan.fetch(:period),
                      familySharable: false, groupLevel: 1, availableInAllTerritories: true,
                      reviewNote: 'One subscription unlocks the four original Simula Pro exam practice modules.'},
                     {group: {data: {type: 'subscriptionGroups', id: group_id}}})
    puts "Created #{plan.fetch(:id)}"
  end
  product_id = product.fetch('id')
  localizations = list("/v1/subscriptions/#{product_id}/subscriptionLocalizations?limit=200")
  unless localizations.any? { |x| x.dig('attributes', 'locale') == 'en-US' }
    create('subscriptionLocalizations', '/v1/subscriptionLocalizations',
           {name: plan.fetch(:name), locale: 'en-US', description: plan.fetch(:description)},
           {subscription: {data: {type: 'subscriptions', id: product_id}}})
    puts "Created en-US localization for #{plan.fetch(:id)}"
  end
  price_points = list("/v1/subscriptions/#{product_id}/pricePoints?filter%5Bterritory%5D=USA&limit=200")
  point = price_points.find { |p| p.dig('attributes', 'customerPrice') == plan.fetch(:price) }
  abort "USA price point #{plan.fetch(:price)} unavailable for #{plan.fetch(:id)}" unless point
  existing_prices = list("/v1/subscriptions/#{product_id}/prices?filter%5Bterritory%5D=USA&limit=200")
  if existing_prices.empty?
    create('subscriptionPrices', '/v1/subscriptionPrices',
           {startDate: nil},
           {subscription: {data: {type: 'subscriptions', id: product_id}},
            subscriptionPricePoint: {data: {type: 'subscriptionPricePoints', id: point.fetch('id')}}})
    puts "Set USA base price $#{plan.fetch(:price)} for #{plan.fetch(:id)}"
  else
    puts "Existing USA price records for #{plan.fetch(:id)}: #{existing_prices.length}; left unchanged"
  end
  current = api('GET', "/v1/subscriptions/#{product_id}").fetch('data')
  puts "Product #{plan.fetch(:id)} state=#{current.dig('attributes', 'state')} period=#{current.dig('attributes', 'subscriptionPeriod')}"
end

