
def patch_server(host)
  data = YAML.load_file('openapi/api/v1/openapi.yaml')
  data['servers'][0]['url'] = host + '/api/v1'
  File.open('openapi/api/v1/openapi.yaml', 'w') { |f| f.write data.to_yaml }
end

Rswag::Ui.configure do |c|

  if ENV['API_HOST'].present?
    patch_server(ENV['API_HOST'])
  end

  # List the Swagger endpoints that you want to be documented through the swagger-ui
  # The first parameter is the path (absolute or relative to the UI host) to the corresponding
  # endpoint and the second is a title that will be displayed in the document selector
  # NOTE: If you're using rspec-api to expose Swagger files (under openapi_root) as JSON or YAML endpoints,
  # then the list below should correspond to the relative paths for those endpoints

  c.openapi_endpoint '/docs/api/v1/openapi.yaml', 'API V1 Docs'

  # Add Basic Auth in case your API is private
  # c.basic_auth_enabled = true
  # c.basic_auth_credentials 'username', 'password'
end
