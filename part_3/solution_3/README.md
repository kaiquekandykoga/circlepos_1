# Part 3 - ISBN-13 Endpoint

A small Rails 8.1 API app (Ruby 4.0.9) with one GET endpoint. It takes the
first 12 digits of an ISBN-13 and returns the check digit and the full ISBN,
using the algorithm from Part 1. It has no database tables.

```
GET /isbn13?prefix=978014300723
```

## Implementation Summary

Each layer has one job:

| Layer | File | Responsibility |
| --- | --- | --- |
| Routing | `config/routes.rb` | Maps `GET /isbn13` to `Isbn13Controller#show`. |
| Request validation | `app/models/isbn13.rb` (ActiveModel validations) | `prefix` must be present and exactly 12 digits. |
| Business logic | `app/models/isbn13.rb` (`#check_digit`, `#to_s`) | Weighted 1/3 sum, mod 10, subtract from 10 (10 becomes 0). |
| Output shaping | `app/controllers/isbn13_controller.rb` | Builds the JSON body and picks the status code (200 / 422). |

Why I split it this way:

- **The controller is thin.** It only handles HTTP: it whitelists params, calls
  the model, and renders JSON. It has no ISBN logic.
- **The model is a plain Ruby object** (`ActiveModel::Model`). The rules are
  plain calculations, so they don't need a table. Using ActiveModel validations
  gives the same `errors` API as any Rails model, so the controller handles
  errors the usual Rails way.
- **`params.permit(:prefix)`** only accepts a scalar value. Arrays or hashes
  are dropped, so they fail validation instead of reaching the logic.
- **Errors use one predictable shape:** `422` with `{ "errors": { field: [messages] } }`.

## Key Code

```ruby
# app/models/isbn13.rb
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
```

```ruby
# app/controllers/isbn13_controller.rb
class Isbn13Controller < ApplicationController
  def show
    isbn = Isbn13.new(prefix: params.permit(:prefix)[:prefix])

    if isbn.valid?
      render json: { prefix: isbn.prefix, check_digit: isbn.check_digit, isbn: isbn.to_s }
    else
      render json: { errors: isbn.errors.to_hash(true) }, status: :unprocessable_content
    end
  end
end
```

## How You Verified It

Automated tests (`bin/rails test`): 8 runs, 24 assertions, 0 failures.

- `test/models/isbn13_test.rb`: the spec example (`978014300723` gives `9780143007234`),
  the case where the check digit becomes 0, a missing prefix, and malformed
  prefixes (too short, too long, letters, dashes, whitespace).
- `test/controllers/isbn13_controller_test.rb`: the 200 response body, a 422
  for a missing prefix, a 422 for a malformed prefix, and an array param being rejected.

Lint: `bin/rubocop` reports no offenses.

Manual check against a running server:

```
$ bin/rails server
$ curl -i "localhost:3000/isbn13?prefix=978014300723"
HTTP/1.1 200 OK
{"prefix":"978014300723","check_digit":4,"isbn":"9780143007234"}

$ curl -i "localhost:3000/isbn13"
HTTP/1.1 422 Unprocessable Content
{"errors":{"prefix":["Prefix can't be blank"]}}

$ curl -i "localhost:3000/isbn13?prefix=12345"
HTTP/1.1 422 Unprocessable Content
{"errors":{"prefix":["Prefix must be exactly 12 digits"]}}
```

## Run It

```
bundle install
bin/rails test
bin/rails server
```
