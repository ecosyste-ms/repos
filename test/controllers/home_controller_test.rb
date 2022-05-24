require 'test_helper'

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do

  end

  test 'renders index' do
    get root_path
    assert_response :success
    assert_template 'home/index'
  end
end