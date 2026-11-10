require "test_helper"

class Isbn13ControllerTest < ActionDispatch::IntegrationTest
  test "returns the full ISBN for a valid prefix" do
    get isbn13_path(prefix: "978014300723")

    assert_response :ok
    assert_equal({ "prefix" => "978014300723", "check_digit" => 4, "isbn" => "9780143007234" }, response.parsed_body)
  end

  test "returns 422 when the prefix is missing" do
    get isbn13_path

    assert_response :unprocessable_content
    assert_equal({ "errors" => { "prefix" => [ "Prefix can't be blank" ] } }, response.parsed_body)
  end

  test "returns 422 when the prefix is malformed" do
    get isbn13_path(prefix: "97801430072x")

    assert_response :unprocessable_content
    assert_equal({ "errors" => { "prefix" => [ "Prefix must be exactly 12 digits" ] } }, response.parsed_body)
  end

  test "ignores non-scalar prefix params" do
    get isbn13_path(prefix: [ "978014300723" ])

    assert_response :unprocessable_content
  end
end
