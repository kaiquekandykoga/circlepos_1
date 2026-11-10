# Tests for solution_2.rb, one class per issue in ISSUES.md.
# Real ActiveJob and ActiveRecord (in-memory SQLite); only GiftCardService is faked.

require "test/unit"
require "logger"
require "active_record"
require "active_job"
require "active_support/core_ext/integer/time"

ActiveRecord::Base.logger = nil
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:sites, &:timestamps)
  create_table :gift_card_transactions do |t|
    t.string :card_number, null: false
    t.boolean :refunded, null: false, default: false
    t.timestamps
  end
end

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil)

class ApplicationJob < ActiveJob::Base; end
class Site < ActiveRecord::Base; end

class GiftCardTransaction < ActiveRecord::Base
  # Stands in for real side effects (audit, webhooks) that update_column skips.
  cattr_accessor :refund_callbacks, default: []
  after_save { refund_callbacks << id if saved_change_to_refunded? }

  validates :card_number, presence: true
end

class GiftCardService
  class << self
    attr_accessor :response, :error, :calls, :on_undo
  end

  def initialize(**) = nil

  def undo
    self.class.calls += 1
    self.class.on_undo&.call
    raise self.class.error if self.class.error

    self.class.response
  end
end

require_relative "solution_2"

class GiftCardUndoJobTestCase < Test::Unit::TestCase
  REMOTE_ID = "remote-123"

  def setup
    GiftCardService.response = { "ResponseCode" => "0" }
    GiftCardService.error = nil
    GiftCardService.on_undo = nil
    GiftCardService.calls = 0
    GiftCardTransaction.refund_callbacks = []
    enqueued_jobs.clear

    @site = Site.create!
    @transaction = GiftCardTransaction.create!(card_number: "6006491234567890")
  end

  def teardown
    GiftCardTransaction.remove_method(:update!) if GiftCardTransaction.method_defined?(:update!, false)
    GiftCardTransaction.delete_all
    Site.delete_all
  end

  private

  def run_job = GiftCardUndoJob.perform_now(@site.id, @transaction.id, REMOTE_ID)
  def enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
  def refunded? = @transaction.reload.refunded?
end

# Issue 1: the same undo must not reach the provider twice.
class TestIssue1Idempotency < GiftCardUndoJobTestCase
  def test_already_refunded_skips_provider
    @transaction.update!(refunded: true)
    run_job
    assert_equal 0, GiftCardService.calls
    assert_empty enqueued_jobs
  end

  def test_enqueued_twice_calls_provider_once
    run_job
    run_job
    assert_equal 1, GiftCardService.calls
  end

  def test_rechecks_db_under_lock
    stale = GiftCardTransaction.find(@transaction.id)
    GiftCardTransaction.where(id: @transaction.id).update_all(refunded: true)
    GiftCardTransaction.define_singleton_method(:find) { |*| stale }
    run_job
    assert_equal 0, GiftCardService.calls
  ensure
    GiftCardTransaction.singleton_class.remove_method(:find)
  end

  def test_save_failure_after_provider_success_does_not_resend
    GiftCardService.on_undo = lambda do
      GiftCardTransaction.define_method(:update!) { |*| raise ActiveRecord::ConnectionFailed }
    end
    run_job
    assert_equal 1, GiftCardService.calls
    assert_empty enqueued_jobs
  end

  def test_provider_error_still_retries
    GiftCardService.error = Timeout::Error
    run_job
    assert_equal 1, enqueued_jobs.size
    refute refunded?
  end
end

# Issue 2: a missing or garbled ResponseCode must not count as success.
class TestIssue2ResponseCode < GiftCardUndoJobTestCase
  SUCCESS = { "string_zero" => "0", "integer_zero" => 0, "padded_zero" => "00" }.freeze
  FAILURE = {
    "missing_code" => {},
    "nil_code" => { "ResponseCode" => nil },
    "empty_code" => { "ResponseCode" => "" },
    "text_code" => { "ResponseCode" => "ERR" },
    "zero_then_text" => { "ResponseCode" => "0ERR" },
    "nonzero_code" => { "ResponseCode" => "51" },
    "nil_response" => nil,
    "html_response" => "<html>Service Unavailable</html>"
  }.freeze

  SUCCESS.each do |name, code|
    define_method("test_#{name}_is_success") do
      GiftCardService.response = { "ResponseCode" => code }
      run_job
      assert refunded?
      assert_empty enqueued_jobs
    end
  end

  FAILURE.each do |name, response|
    define_method("test_#{name}_is_failure") do
      GiftCardService.response = response
      run_job
      refute refunded?
      assert_equal 1, enqueued_jobs.size
    end
  end
end

# Issue 3: the refund must run callbacks, validations and bump updated_at.
class TestIssue3UpdateCallbacks < GiftCardUndoJobTestCase
  def test_runs_callbacks
    run_job
    assert_equal [@transaction.id], GiftCardTransaction.refund_callbacks
  end

  def test_bumps_updated_at
    old_time = 1.day.ago.change(usec: 0)
    @transaction.update_columns(updated_at: old_time)
    run_job
    assert_operator @transaction.reload.updated_at, :>, old_time
  end

  def test_runs_validations
    @transaction.update_columns(card_number: "")
    run_job
    refute refunded?
    assert_empty enqueued_jobs # provider already undid it, so no retry (issue 1)
  end
end
