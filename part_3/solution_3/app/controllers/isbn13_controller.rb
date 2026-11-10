class Isbn13Controller < ApplicationController
  # GET /isbn13?prefix=978014300723
  def show
    isbn = Isbn13.new(prefix: params.permit(:prefix)[:prefix])

    if isbn.valid?
      render json: { prefix: isbn.prefix, check_digit: isbn.check_digit, isbn: isbn.to_s }
    else
      render json: { errors: isbn.errors.to_hash(true) }, status: :unprocessable_content
    end
  end
end
