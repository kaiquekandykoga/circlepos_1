require "test/unit"
require_relative "solution_1"

class TestSolution1 < Test::Unit::TestCase
  def test_example_from_problem
    assert_equal "9780143007234", isbn13("978014300723")
  end

  def test_check_digit_0
    assert_equal "9780143007210", isbn13("978014300721")
  end

  def test_check_digit_1
    assert_equal "9780143007241", isbn13("978014300724")
  end

  def test_check_digit_2
    assert_equal "9780143007272", isbn13("978014300727")
  end

  def test_check_digit_3
    assert_equal "9780143007203", isbn13("978014300720")
  end

  def test_check_digit_4
    assert_equal "9780143007234", isbn13("978014300723")
  end

  def test_check_digit_5
    assert_equal "9780143007265", isbn13("978014300726")
  end

  def test_check_digit_6
    assert_equal "9780143007296", isbn13("978014300729")
  end

  def test_check_digit_7
    assert_equal "9780143007227", isbn13("978014300722")
  end

  def test_check_digit_8
    assert_equal "9780143007258", isbn13("978014300725")
  end

  def test_check_digit_9
    assert_equal "9780143007289", isbn13("978014300728")
  end

  def test_rejects_too_short
    assert_raise(ArgumentError) { isbn13("97801430072") }
  end

  def test_rejects_too_long
    assert_raise(ArgumentError) { isbn13("9780143007234") }
  end

  def test_rejects_non_digits
    assert_raise(ArgumentError) { isbn13("97801430072a") }
  end

  def test_rejects_hyphens
    assert_raise(ArgumentError) { isbn13("978-01430072") }
  end

  def test_rejects_empty
    assert_raise(ArgumentError) { isbn13("") }
  end

  def test_rejects_trailing_newline
    assert_raise(ArgumentError) { isbn13("978014300723\n") }
  end

  def test_rejects_non_string
    assert_raise(ArgumentError) { isbn13(978014300723) }
  end

  def test_rejects_nil
    assert_raise(ArgumentError) { isbn13(nil) }
  end
end
