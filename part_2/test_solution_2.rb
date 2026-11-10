# Unit tests for the GiftCardUndoJob patch in solution_2.rb.
#
# Runs the job against real ActiveJob (test adapter) and ActiveRecord
# (in-memory SQLite). Only GiftCardService, the external provider, is faked.
#
# Tests are grouped by the issue they cover (see ISSUES.md):
#   TestIssue1Idempotency      - issue 1: same undo must not reach the provider twice
#   TestIssue2ResponseCode     - issue 2: missing/garbled ResponseCode must not count as success
#   TestIssue3UpdateCallbacks  - issue 3: refund must run validations, callbacks and bump updated_at

require "test/unit"
require "logger"
require "active_record"
require "active_job"
require "active_support/core_ext/integer/time"

# --- Minimal Rails app environment ------------------------------------------

ActiveRecord::Base.logger = nil
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :sites do |t|
    t.timestamps
  end

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
  # Stands in for real after-save side effects (audit log, balance sync,
  # webhooks). update_column skips these; update! runs them.
  cattr_accessor :refund_callbacks, default: []
  after_save { refund_callbacks << id if saved_change_to_refunded? }

  validates :card_number, presence: true
end

# Fake provider client. Each test sets the response (or an error to raise)
# and reads back how many times the provider was called.
class GiftCardService
  class << self
    attr_accessor :response, :error, :calls, :on_undo
  end

  def initialize(site:, card_number:, remote_transaction_id:)
    @args = { site: site, card_number: card_number, remote_transaction_id: remote_transaction_id }
  end

  def undo
    self.class.calls << @args
    self.class.on_undo&.call
    raise self.class.error if self.class.error

    self.class.response
  end
end

require_relative "solution_2"

# --- Shared setup -----------------------------------------------------------

class GiftCardUndoJobTestCase < Test::Unit::TestCase
  REMOTE_ID = "remote-123"

  def setup
    GiftCardService.response = { "ResponseCode" => "0" }
    GiftCardService.error = nil
    GiftCardService.on_undo = nil
    GiftCardService.calls = []
    GiftCardTransaction.refund_callbacks = []
    enqueued_jobs.clear

    @site = Site.create!
    @transaction = GiftCardTransaction.create!(card_number: "6006491234567890")
  end

  def teardown
    # Drop an update! stub left behind if the job never called it.
    GiftCardTransaction.remove_method(:update!) if GiftCardTransaction.method_defined?(:update!, false)
    GiftCardTransaction.delete_all
    Site.delete_all
  end

  private

  def run_job
    GiftCardUndoJob.perform_now(@site.id, @transaction.id, REMOTE_ID)
  end

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  def provider_calls
    GiftCardService.calls.size
  end

  def assert_retry_enqueued
    assert_equal 1, enqueued_jobs.size, "expected exactly one retry to be enqueued"
    assert_equal [@site.id, @transaction.id, REMOTE_ID], enqueued_jobs.first["arguments"]
  end

  def assert_no_retry_enqueued
    assert_empty enqueued_jobs, "expected no retry to be enqueued"
  end
end

# --- Issue 1: no idempotency guard, so the same undo can run twice ----------

class TestIssue1Idempotency < GiftCardUndoJobTestCase
  def test_already_refunded_transaction_does_not_call_provider
    @transaction.update!(refunded: true)

    run_job

    assert_equal 0, provider_calls
    assert_no_retry_enqueued
  end

  def test_job_enqueued_twice_calls_provider_only_once
    run_job
    run_job

    assert_equal 1, provider_calls
    assert @transaction.reload.refunded?
  end

  def test_refunded_state_is_rechecked_from_the_db_under_the_lock
    # Another worker refunded the row after this job loaded its (now stale)
    # copy. with_lock reloads, so the guard must see the DB value.
    stale = GiftCardTransaction.find(@transaction.id)
    GiftCardTransaction.where(id: @transaction.id).update_all(refunded: true)
    stub_find_to_return(stale) { run_job }

    assert_equal 0, provider_calls
  end

  def test_provider_success_but_db_save_fails_does_not_resend_undo
    GiftCardService.on_undo = -> { make_next_save_fail(ActiveRecord::ConnectionFailed) }

    run_job # UndoNotRecordedError is discarded via discard_on, not re-raised

    assert_equal 1, provider_calls
    assert_no_retry_enqueued
    refute @transaction.reload.refunded?
  end

  def test_provider_success_but_validation_fails_does_not_resend_undo
    GiftCardService.on_undo = -> { make_next_save_fail(ActiveRecord::RecordInvalid) }

    run_job

    assert_equal 1, provider_calls
    assert_no_retry_enqueued
  end

  def test_unrecorded_undo_is_discarded_with_the_dedicated_error
    GiftCardService.on_undo = -> { make_next_save_fail(ActiveRecord::ConnectionFailed) }
    discarded = []
    subscriber = ActiveSupport::Notifications.subscribe("discard.active_job") do |*, payload|
      discarded << payload[:error]
    end

    run_job

    assert_equal 1, discarded.size
    assert_kind_of GiftCardUndoJob::UndoNotRecordedError, discarded.first
    assert_match(/remote_transaction_id=#{REMOTE_ID}/, discarded.first.message)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def test_provider_error_before_confirmation_still_retries
    GiftCardService.error = Timeout::Error

    run_job

    assert_equal 1, provider_calls
    assert_retry_enqueued
    refute @transaction.reload.refunded?
  end

  private

  def stub_find_to_return(record)
    # find is inherited from ActiveRecord, so removing the singleton override restores it.
    GiftCardTransaction.define_singleton_method(:find) { |*| record }
    yield
  ensure
    GiftCardTransaction.singleton_class.remove_method(:find)
  end

  # Makes the next update! on any GiftCardTransaction raise, simulating a DB
  # failure right after the provider confirmed the undo.
  def make_next_save_fail(error_class)
    GiftCardTransaction.class_eval do
      define_method(:update!) do |*|
        GiftCardTransaction.remove_method(:update!)
        raise error_class == ActiveRecord::RecordInvalid ? error_class.new(self) : error_class
      end
    end
  end
end

# --- Issue 2: a missing or garbled ResponseCode counts as success -----------

class TestIssue2ResponseCode < GiftCardUndoJobTestCase
  SUCCESS_RESPONSES = {
    "string zero" => { "ResponseCode" => "0" },
    "integer zero" => { "ResponseCode" => 0 },
    "zero padded" => { "ResponseCode" => "00" }
  }.freeze

  FAILURE_RESPONSES = {
    "missing code" => { "Message" => "Internal error" },
    "nil code" => { "ResponseCode" => nil },
    "empty code" => { "ResponseCode" => "" },
    "non-numeric code" => { "ResponseCode" => "ERR" },
    "code with leading zero then text" => { "ResponseCode" => "0ERR" },
    "non-zero code" => { "ResponseCode" => "51" },
    "empty hash" => {},
    "nil response" => nil,
    "html maintenance page" => "<html>Service Unavailable</html>"
  }.freeze

  SUCCESS_RESPONSES.each do |label, response|
    define_method("test_#{label.tr(' -', '__')}_marks_refunded") do
      GiftCardService.response = response

      run_job

      assert @transaction.reload.refunded?, "#{response.inspect} should count as success"
      assert_no_retry_enqueued
    end
  end

  FAILURE_RESPONSES.each do |label, response|
    define_method("test_#{label.tr(' -', '__')}_is_not_marked_refunded_and_retries") do
      GiftCardService.response = response

      run_job

      refute @transaction.reload.refunded?, "#{response.inspect} must not count as success"
      assert_retry_enqueued
    end
  end
end

# --- Issue 3: update_column skips callbacks, validations and updated_at -----

class TestIssue3UpdateCallbacks < GiftCardUndoJobTestCase
  def test_refund_runs_model_callbacks
    run_job

    assert_equal [@transaction.id], GiftCardTransaction.refund_callbacks
  end

  def test_refund_bumps_updated_at
    old_time = 1.day.ago.change(usec: 0)
    @transaction.update_columns(updated_at: old_time)

    run_job

    assert_operator @transaction.reload.updated_at, :>, old_time
  end

  def test_refund_runs_validations
    # An invalid row is not silently written. The provider has already
    # confirmed the undo, so the job is discarded (issue 1) rather than retried.
    @transaction.update_columns(card_number: "")

    run_job

    refute @transaction.reload.refunded?
    assert_empty GiftCardTransaction.refund_callbacks
    assert_no_retry_enqueued
  end

  def test_refund_is_logged_for_audit_trail
    io = StringIO.new
    original_logger = ActiveJob::Base.logger
    ActiveJob::Base.logger = Logger.new(io)

    run_job

    assert_match(/refunded transaction_id=#{@transaction.id} remote_transaction_id=#{REMOTE_ID} response_code="0"/, io.string)
  ensure
    ActiveJob::Base.logger = original_logger
  end
end
