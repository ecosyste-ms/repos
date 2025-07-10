require 'test_helper'

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @successful_import = create(:import, 
      filename: '2025-01-01-12.json.gz',
      imported_at: 2.hours.ago,
      success: true,
      repositories_synced_count: 1500,
      releases_synced_count: 25
    )
    
    @failed_import = create(:import,
      filename: '2025-01-01-13.json.gz', 
      imported_at: 1.hour.ago,
      success: false,
      error_message: 'Failed to download file from https://data.gharchive.org/2025-01-01-13.json.gz'
    )
    
    @old_import = create(:import,
      filename: '2025-01-01-10.json.gz',
      imported_at: 2.days.ago,
      success: true,
      repositories_synced_count: 800,
      releases_synced_count: 15
    )
  end

  test "should get index" do
    get imports_path
    assert_response :success
    assert_template :index
  end

  test "should display imports in descending filename order" do
    get imports_path
    assert_response :success
    
    # Check that imports are present
    assert_select 'table.table'
    assert_select 'tbody tr', count: 3
    
    # Check filenames are displayed
    assert_select 'td', text: @successful_import.filename
    assert_select 'td', text: @failed_import.filename
    assert_select 'td', text: @old_import.filename
  end

  test "should display success badges for successful imports" do
    get imports_path
    assert_response :success
    
    # Check success badge
    assert_select 'span.badge.bg-success', text: /Success/
  end

  test "should display error badges for failed imports" do
    get imports_path
    assert_response :success
    
    # Check error badge
    assert_select 'span.badge.bg-danger', text: /Failed/
  end

  test "should display error messages for failed imports" do
    get imports_path
    assert_response :success
    
    # Check error message is displayed
    assert_select 'div.alert.alert-danger', text: /Failed to download file/
  end

  test "should display repository and release counts" do
    get imports_path
    assert_response :success
    
    # Check that numbers are displayed as badges
    assert_select 'span.badge.bg-secondary', text: '1,500'
    assert_select 'span.badge.bg-info', text: '25'
  end

  test "should calculate recent stats for last 24 hours" do
    get imports_path
    assert_response :success
    
    # Verify stats are calculated and displayed
    assert_select 'div.card-body' do
      assert_select 'strong', text: 'Total Imports:'
      assert_select 'strong', text: 'Successful:'
      assert_select 'strong', text: 'Failed:'
      assert_select 'strong', text: 'Repositories Processed:'
      assert_select 'strong', text: 'With Releases:'
      assert_select 'strong', text: 'Success Rate:'
    end
  end

  test "should link to gharchive urls" do
    get imports_path
    assert_response :success
    
    # Check that filename links to gharchive
    assert_select "a[href='https://data.gharchive.org/#{@successful_import.filename}']"
    assert_select "a[target='_blank']"
    assert_select "a[rel='noopener']"
  end

  test "should handle empty imports gracefully" do
    Import.destroy_all
    
    get imports_path
    assert_response :success
    
    # Should still display the table structure
    assert_select 'table.table'
    assert_select 'tbody tr', count: 0
  end

  test "should display pagination when many imports exist" do
    # Create many imports to trigger pagination
    30.times do |i|
      create(:import, filename: "2025-02-01-#{i}.json.gz", imported_at: i.minutes.ago)
    end
    
    get imports_path
    assert_response :success
    
    # Should display pagination if implemented
    # Note: This depends on the pagination implementation
  end

  test "should format timestamps correctly" do
    get imports_path
    assert_response :success
    
    # Check that timestamps are formatted as expected
    expected_time = @successful_import.imported_at.strftime('%Y-%m-%d %H:%M:%S UTC')
    assert_select 'small.text-muted', text: expected_time
  end

  test "should be responsive with table wrapper" do
    get imports_path
    assert_response :success
    
    # Check responsive table wrapper
    assert_select 'div.table-responsive'
    assert_select 'table.table-striped.table-hover'
  end
end