#!/usr/bin/env ruby
# Upload real, visually checked screenshots. No prices or review submissions.
require 'digest'
require_relative 'configure_module_subscriptions'

root = File.expand_path(ENV.fetch('SUBSCRIPTION_SCREENSHOT_DIR'))
report_path = 'artifacts/module-subscriptions-report.json'
report = JSON.parse(File.read(report_path))
module_keys = {'psychologylaw'=>'psychologyLaw', 'pmicp'=>'pmiCP', 'gc'=>'gc', 'fe'=>'fe'}
pending = []

def commit_screenshot(id, checksum)
  uri = URI("https://api.appstoreconnect.apple.com/v1/subscriptionAppStoreReviewScreenshots/#{id}")
  request = Net::HTTP::Patch.new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(data: {type: 'subscriptionAppStoreReviewScreenshots', id: id,
                                      attributes: {uploaded: true, sourceFileChecksum: checksum}})
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 35) { |http| http.request(request) }
  unless response.code.to_i == 200
    codes = (JSON.parse(response.body).fetch('errors', []).map { |e| e['code'] }.join(',') rescue 'unparseable response')
    abort "Screenshot commit failed: HTTP #{response.code}, #{codes}"
  end
end

report.fetch('products').each do |product|
  product_id = product.fetch('product_id')
  module_key = module_keys.fetch(product_id.split('.')[2])
  path = File.join(root, "review-#{module_key}.png")
  abort "Screenshot missing: #{File.basename(path)}" unless File.file?(path)
  bytes = File.binread(path)
  abort 'Invalid PNG screenshot' unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)
  width, height = bytes.byteslice(16, 8).unpack('NN')
  abort "Unexpected screenshot dimensions: #{width}x#{height}" unless width >= 1000 && height >= 2000
  checksum = Digest::MD5.hexdigest(bytes)
  existing = api('GET', "/v1/subscriptions/#{product.fetch('apple_id')}/appStoreReviewScreenshot", optional: true)&.fetch('data', nil)
  if existing
    puts "Preserved existing review screenshot for #{product_id}"
    pending << [product, existing.fetch('id')]
    next
  end
  resource = create('subscriptionAppStoreReviewScreenshots', '/v1/subscriptionAppStoreReviewScreenshots',
                    {fileName: File.basename(path), fileSize: bytes.bytesize},
                    {subscription: {data: {type: 'subscriptions', id: product.fetch('apple_id')}}})
  operations = resource.fetch('attributes').fetch('uploadOperations')
  abort 'Apple returned no screenshot upload operation' if operations.empty?
  operations.each do |operation|
    uri = URI(operation.fetch('url'))
    abort 'Screenshot upload requires HTTPS' unless uri.scheme == 'https'
    abort 'Unexpected upload method' unless operation.fetch('method') == 'PUT'
    request = Net::HTTP::Put.new(uri)
    operation.fetch('requestHeaders', []).each { |h| request[h.fetch('name')] = h.fetch('value') }
    request.body = bytes.byteslice(operation.fetch('offset'), operation.fetch('length'))
    # The signed asset-upload URL receives only Apple's supplied headers, not API credentials.
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |http| http.request(request) }
    abort "Image upload failed: HTTP #{response.code}" unless [200, 201, 204].include?(response.code.to_i)
  end
  commit_screenshot(resource.fetch('id'), checksum)
  pending << [product, resource.fetch('id')]
  puts "Uploaded review screenshot for #{product_id}: #{width}x#{height}"
end

pending.each do |product, id|
  state = nil
  20.times do
    screenshot = api('GET', "/v1/subscriptionAppStoreReviewScreenshots/#{id}").fetch('data')
    state = screenshot.dig('attributes', 'assetDeliveryState', 'state')
    break if ['COMPLETE', 'FAILED'].include?(state)
    sleep 3
  end
  abort "Screenshot not ready for #{product.fetch('product_id')}: #{state}" unless state == 'COMPLETE'
  product['review_screenshot_present'] = true
  product['review_screenshot_state'] = state
  current = api('GET', "/v1/subscriptions/#{product.fetch('apple_id')}").fetch('data')
  product['state'] = current.dig('attributes', 'state')
  product['version_states'] = list("/v1/subscriptions/#{product.fetch('apple_id')}/versions?limit=200").map { |v| v.dig('attributes', 'state') }
  puts "VERIFIED #{product.fetch('product_id')}: screenshot=#{state}, product=#{product['state']}, versions=#{product['version_states'].join(',')}"
end
report['needs_review_screenshot'] = []
report['ready_for_review'] = report.fetch('needs_price_decision').empty? && report.fetch('products').all? { |p| p['version_states'].include?('READY_FOR_REVIEW') }
File.write(report_path, JSON.pretty_generate(report))
puts "Verified screenshots for #{pending.length} plans. Recurring prices remain unchanged. Nothing submitted for review."
