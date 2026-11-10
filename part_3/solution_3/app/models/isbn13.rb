# Business logic: builds a full ISBN-13 from its first 12 digits.
# Plain Ruby object with ActiveModel validations - no database table.
class Isbn13
  include ActiveModel::Model

  WEIGHTS = [ 1, 3 ].cycle.first(12).freeze

  attr_accessor :prefix

  validates :prefix, presence: true
  validates :prefix, format: { with: /\A\d{12}\z/, message: "must be exactly 12 digits" }, allow_blank: true

  def check_digit
    sum = prefix.chars.zip(WEIGHTS).sum { |digit, weight| digit.to_i * weight }
    (10 - sum % 10) % 10
  end

  def to_s
    "#{prefix}#{check_digit}"
  end
end
