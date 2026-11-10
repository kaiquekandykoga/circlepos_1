require "rails_helper"

RSpec.describe "GET /isbn13", type: :request do
  it "returns the full ISBN for a valid prefix" do
    get isbn13_path(prefix: "978014300723")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("prefix" => "978014300723", "check_digit" => 4, "isbn" => "9780143007234")
  end

  it "returns 422 when the prefix is missing" do
    get isbn13_path

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("errors" => { "prefix" => [ "Prefix can't be blank" ] })
  end

  it "returns 422 when the prefix is malformed" do
    get isbn13_path(prefix: "97801430072x")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("errors" => { "prefix" => [ "Prefix must be exactly 12 digits" ] })
  end

  it "ignores non-scalar prefix params" do
    get isbn13_path(prefix: [ "978014300723" ])

    expect(response).to have_http_status(:unprocessable_content)
  end
end
