require 'test_helper'

class CacheHeadersTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
  end

  test 'html pages set CDN-Cache-Control with 4 hour max-age' do
    get root_path
    assert_response :success
    assert_match /max-age=#{4.hours.to_i}/, response.headers['CDN-Cache-Control']
  end

  test 'html pages set CDN-Cache-Control with 1 day stale-while-revalidate' do
    get root_path
    assert_response :success
    assert_match /stale-while-revalidate=#{1.day.to_i}/, response.headers['CDN-Cache-Control']
  end

  test 'html pages set public cache control' do
    get root_path
    assert_response :success
    assert_match /public/, response.headers['Cache-Control']
  end

  test 'pages without explicit expires_in get 5 minute browser max-age' do
    get exports_path
    assert_response :success
    assert_match /max-age=#{5.minutes.to_i}/, response.headers['Cache-Control']
  end

  test 'pages without explicit expires_in get browser stale-while-revalidate' do
    get exports_path
    assert_response :success
    assert_match /stale-while-revalidate=#{1.hour.to_i}/, response.headers['Cache-Control']
  end

  test 'pages with explicit expires_in keep their browser max-age' do
    get root_path
    assert_response :success
    assert_match /max-age=#{1.day.to_i}/, response.headers['Cache-Control']
  end

  test 'api endpoints set CDN-Cache-Control with 1 hour max-age' do
    get api_v1_hosts_path(format: :json)
    assert_response :success
    assert_match /max-age=#{1.hour.to_i}/, response.headers['CDN-Cache-Control']
  end

  test 'api endpoints set CDN-Cache-Control with 4 hour stale-while-revalidate' do
    get api_v1_hosts_path(format: :json)
    assert_response :success
    assert_match /stale-while-revalidate=#{4.hours.to_i}/, response.headers['CDN-Cache-Control']
  end

  test 'host show page sets CDN-Cache-Control' do
    get host_path(@host)
    assert_response :success
    assert_match /max-age=#{4.hours.to_i}/, response.headers['CDN-Cache-Control']
  end
end
