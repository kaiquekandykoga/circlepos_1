def isbn13(input)
  raise ArgumentError, "input must be exactly 12 digits" unless input.is_a?(String) && input.match?(/\A\d{12}\z/)

  digits = input.chars.map(&:to_i)
  weighted = digits.each_with_index.map { |digit, i| digit * (i.even? ? 1 : 3) }

  sum = weighted.sum           # 1. Sum
  remainder = sum % 10         # 2. Mod 10
  check = 10 - remainder       # 3. Subtract
  check = 0 if check == 10     # 4. If it's 10, use 0

  input + check.to_s
end

if __FILE__ == $0
  begin
    puts isbn13(ARGV.fetch(0, ""))
  rescue ArgumentError => e
    warn e.message
    exit 1
  end
end
