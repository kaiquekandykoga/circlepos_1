require "rails_helper"

RSpec.describe Isbn13 do
  it "calculates the check digit from the spec example" do
    isbn = described_class.new(prefix: "978014300723")

    expect(isbn).to be_valid
    expect(isbn.check_digit).to eq(4)
    expect(isbn.to_s).to eq("9780143007234")
  end

  it "uses 0 when 10 minus the remainder is 10" do
    expect(described_class.new(prefix: "000000000000").check_digit).to eq(0)
    expect(described_class.new(prefix: "978030640615").to_s).to eq("9780306406157")
  end

  it "requires a prefix" do
    isbn = described_class.new(prefix: nil)

    expect(isbn).not_to be_valid
    expect(isbn.errors[:prefix]).to eq([ "can't be blank" ])
  end

  [ "97801430072", "9780143007234", "97801430072a", "978-014300723", " 978014300723" ].each do |prefix|
    it "rejects #{prefix.inspect}" do
      isbn = described_class.new(prefix: prefix)

      expect(isbn).not_to be_valid
      expect(isbn.errors[:prefix]).to eq([ "must be exactly 12 digits" ])
    end
  end
end
