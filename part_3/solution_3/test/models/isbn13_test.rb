require "test_helper"

class Isbn13Test < ActiveSupport::TestCase
  test "calculates the check digit from the spec example" do
    isbn = Isbn13.new(prefix: "978014300723")

    assert isbn.valid?
    assert_equal 4, isbn.check_digit
    assert_equal "9780143007234", isbn.to_s
  end

  test "uses 0 when 10 minus the remainder is 10" do
    assert_equal 0, Isbn13.new(prefix: "000000000000").check_digit
    assert_equal "9780306406157", Isbn13.new(prefix: "978030640615").to_s
  end

  test "requires a prefix" do
    isbn = Isbn13.new(prefix: nil)

    assert_not isbn.valid?
    assert_equal [ "can't be blank" ], isbn.errors[:prefix]
  end

  test "rejects anything that is not exactly 12 digits" do
    [ "97801430072", "9780143007234", "97801430072a", "978-014300723", " 978014300723" ].each do |prefix|
      isbn = Isbn13.new(prefix: prefix)

      assert_not isbn.valid?, "expected #{prefix.inspect} to be invalid"
      assert_equal [ "must be exactly 12 digits" ], isbn.errors[:prefix]
    end
  end
end
