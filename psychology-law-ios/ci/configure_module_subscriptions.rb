#!/usr/bin/env ruby
# Idempotent metadata setup. Never changes prices, existing entitlements, agreements,
# banking/tax details, or submits products for public App Store review.
require 'json'
require 'openssl'
require 'base64'
require 'net/http'
require 'uri'
require 'fileutils'
$stdout.sync = true

%w[APPSTORE_API_KEY_ID APPSTORE_ISSUER_ID APPSTORE_API_PRIVATE_KEY].each do |name|
  abort "Missing #{name}" if ENV[name].to_s.empty?
end

def b64(data) = Base64.urlsafe_encode64(data, padding: false)
now = Time.now.to_i
header = {alg: 'ES256', typ: 'JWT', kid: ENV.fetch('APPSTORE_API_KEY_ID')}
claims = {iss: ENV.fetch('APPSTORE_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1'}
prefix = [header, claims].map { |part| b64(JSON.generate(part)) }.join('.')
key = OpenSSL::PKey.read(ENV.fetch('APPSTORE_API_PRIVATE_KEY'))
signature = OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest.new('SHA256'), prefix)).value.map { |part| [part.value.to_s(16).rjust(64, '0')].pack('H*') }.join
TOKEN = "#{prefix}.#{b64(signature)}"

def api(method, path, body=nil, optional: false)
  uri = path.start_with?('https://') ? URI(path) : URI("https://api.appstoreconnect.apple.com#{path}")
  abort 'Refusing to send Apple credentials to another host' unless uri.scheme == 'https' && uri.host == 'api.appstoreconnect.apple.com'
  request = {'GET'=>Net::HTTP::Get, 'POST'=>Net::HTTP::Post}.fetch(method).new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Accept'] = 'application/json'
  if body
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 35) { |http| http.request(request) }
  return nil if optional && response.code.to_i == 404
  unless [200, 201].include?(response.code.to_i)
    errors = (JSON.parse(response.body)['errors'] rescue [])
    details = Array(errors).map { |e| "#{e['code']}: #{e['detail']}" }.join('; ')
    abort "Apple API #{method} #{uri.path}: HTTP #{response.code}: #{details[0, 700]}"
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
  data = {type: type, relationships: relationships}
  data[:attributes] = attributes unless attributes.empty?
  api('POST', path, {data: data}).fetch('data')
end

app_id = '6823960478'
app = api('GET', "/v1/apps/#{app_id}").fetch('data')
abort 'Unexpected app bundle; no changes made' unless app.dig('attributes', 'bundleId') == 'com.simulapro.psychologylaw'
modules = [
  {key: 'psychologyLaw', name: 'Psychology Law', group: 'Psychology Law Access', prefix: 'com.simulapro.psychologylaw'},
  {key: 'pmiCP', name: 'PMI-CP', group: 'PMI-CP Access', prefix: 'com.simulapro.pmicp'},
  {key: 'gc', name: 'GC Business & Finance', group: 'GC Business & Finance Access', prefix: 'com.simulapro.gc'},
  {key: 'fe', name: 'FE Mechanical', group: 'FE Mechanical Access', prefix: 'com.simulapro.fe'}
]
groups = list("/v1/apps/#{app_id}/subscriptionGroups?limit=200")
report = {app_id: app_id, prices_changed: false, submitted_for_review: false, products: []}
modules.each do |mod|
  group = groups.find { |item| item.dig('attributes', 'referenceName') == mod.fetch(:group) }
  group ||= create('subscriptionGroups', '/v1/subscriptionGroups',
                   {referenceName: mod.fetch(:group)},
                   {app: {data: {type: 'apps', id: app_id}}})
  group_id = group.fetch('id')
  versions = list("/v1/subscriptionGroups/#{group_id}/versions?limit=200")
  version = versions.find { |v| v.dig('attributes', 'state') == 'PREPARE_FOR_SUBMISSION' }
  version ||= create('subscriptionGroupVersions', '/v1/subscriptionGroupVersions', {},
                     {subscriptionGroup: {data: {type: 'subscriptionGroups', id: group_id}}})
  version_id = version.fetch('id')
  locales = list("/v1/subscriptionGroupVersions/#{version_id}/localizations?limit=200")
  unless locales.any? { |x| x.dig('attributes', 'locale') == 'en-US' }
    create('subscriptionGroupLocalizations', '/v2/subscriptionGroupLocalizations',
           {name: mod.fetch(:group), locale: 'en-US'},
           {version: {data: {type: 'subscriptionGroupVersions', id: version_id}}})
    puts "Created group localization: #{mod.fetch(:group)}"
  end
  products = list("/v1/subscriptionGroups/#{group_id}/subscriptions?limit=200")
  [['monthly', 'Monthly', 'ONE_MONTH'], ['yearly', 'Yearly', 'ONE_YEAR']].each do |suffix, duration, period|
    product_id = "#{mod.fetch(:prefix)}.#{suffix}"
    product = products.find { |p| p.dig('attributes', 'productId') == product_id }
    unless product
      product = create('subscriptions', '/v1/subscriptions',
                       {name: "#{mod.fetch(:name)} #{duration}", productId: product_id,
                        subscriptionPeriod: period, familySharable: false, groupLevel: 1,
                        reviewNote: "Access to the #{mod.fetch(:name)} simulator only. Monthly and yearly are alternative durations in this group. Other simulators have separate subscriptions."},
                       {group: {data: {type: 'subscriptionGroups', id: group_id}}})
      puts "Created missing product: #{product_id}"
    end
    id = product.fetch('id')
    abort "Unexpected duration for #{product_id}; no price changes made" unless product.dig('attributes', 'subscriptionPeriod') == period
    localizations = list("/v1/subscriptions/#{id}/subscriptionLocalizations?limit=200")
    unless localizations.any? { |x| x.dig('attributes', 'locale') == 'en-US' }
      create('subscriptionLocalizations', '/v1/subscriptionLocalizations',
             {name: "#{mod.fetch(:name)} #{duration}", locale: 'en-US', description: "#{duration} access to #{mod.fetch(:name)} practice."},
             {subscription: {data: {type: 'subscriptions', id: id}}})
      puts "Created product localization: #{product_id}"
    end
    plans = list("/v1/subscriptions/#{id}/planAvailabilities?limit=200")
    plan = plans.find { |x| x.dig('attributes', 'planType') == 'UPFRONT' }
    unless plan
      plan = create('subscriptionPlanAvailabilities', '/v1/subscriptionPlanAvailabilities',
                    {planType: 'UPFRONT', availableInNewTerritories: false},
                    {subscription: {data: {type: 'subscriptions', id: id}},
                     availableTerritories: {data: [{type: 'territories', id: 'USA'}]}})
      puts "Configured USA availability: #{product_id}"
    end
    territories = list("/v1/subscriptionPlanAvailabilities/#{plan.fetch('id')}/availableTerritories?limit=200")
    prices = list("/v1/subscriptions/#{id}/prices?filter%5Bterritory%5D=USA&limit=200")
    screenshot = api('GET', "/v1/subscriptions/#{id}/appStoreReviewScreenshot", optional: true)
    current = api('GET', "/v1/subscriptions/#{id}").fetch('data')
    item = {product_id: product_id, apple_id: id, group_id: group_id,
            state: current.dig('attributes', 'state'),
            usa_available: territories.any? { |t| t.fetch('id') == 'USA' },
            usa_price_records: prices.length,
            review_screenshot_state: screenshot&.dig('data', 'attributes', 'assetDeliveryState', 'state'),
            review_screenshot_present: !screenshot&.dig('data', 'id').nil?}
    report[:products] << item
    puts "PLAN #{product_id}: #{item.reject { |k, _| [:product_id, :apple_id, :group_id].include?(k) }.to_json}"
  end
end
report[:needs_price_decision] = report[:products].select { |p| p[:usa_price_records].zero? }.map { |p| p[:product_id] }
report[:needs_review_screenshot] = report[:products].reject { |p| p[:review_screenshot_present] }.map { |p| p[:product_id] }
report[:ready_for_review] = report[:needs_price_decision].empty? && report[:needs_review_screenshot].empty? && report[:products].all? { |p| p[:state] == 'READY_TO_SUBMIT' }
FileUtils.mkdir_p('artifacts')
File.write('artifacts/module-subscriptions-report.json', JSON.pretty_generate(report))
puts "Metadata setup finished. Prices changed: false. Submitted for review: false. Ready for review: #{report[:ready_for_review]}"
puts "Products still needing approved recurring prices: #{report[:needs_price_decision].length}"
if ENV['GITHUB_STEP_SUMMARY']
  File.open(ENV['GITHUB_STEP_SUMMARY'], 'a') do |f|
    f.puts "## Per-simulator subscription configuration\n\nNo prices, tax/banking details or agreements were changed. No review was submitted.\n"
    f.puts '| Product | State | USA available | USA price records | Review screenshot |'
    f.puts '| --- | --- | --- | --- | --- |'
    report[:products].each { |p| f.puts "| #{p[:product_id]} | #{p[:state]} | #{p[:usa_available]} | #{p[:usa_price_records]} | #{p[:review_screenshot_present]} |" }
  end
end
