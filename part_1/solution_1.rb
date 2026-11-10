def isbn13(input)
  raise ArgumentError, "input must be exactly 12 digits" unless input.is_a?(String) && input.match?(/\A\d{12}\z/)

  sum = input.chars.each_with_index.sum { |c, i| c.to_i * (i.even? ? 1 : 3) }
  check = (10 - sum % 10) % 10
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
