# Part 2 - Minimal safe patch for GiftCardUndoJob.
#
# Fixes issues 1, 2 and 3 from ISSUES.md. Each change is tagged with
# "FIX #N" so it can be matched to the issue it addresses.
# Issues 4-6 (retry limits, bare rescue, missing records) are out of scope
# for this patch; the retry behaviour for real failures is left as it was.

class GiftCardUndoJob < ApplicationJob
  queue_as :normal_priority

  # FIX #1: the provider already reversed the card but we could not save
  # that. This job must never send the undo again: it is discarded (and
  # logged at error level by ActiveJob) so a human can reconcile, instead
  # of being retried by our own retry_undo or by the queue adapter.
  class UndoNotRecordedError < StandardError; end
  discard_on UndoNotRecordedError

  def perform(site_id, transaction_id, remote_transaction_id)
    transaction = GiftCardTransaction.find(transaction_id)
    site = Site.find(site_id)

    undo_transaction(site, transaction, remote_transaction_id)
  end

  private

  def undo_transaction(site, transaction, remote_transaction_id)
    provider_confirmed = false

    # FIX #1: take a row lock (with_lock also reloads the row) so two copies
    # of this job (double enqueue, redelivery, a retry) can't both reach the
    # provider. The second one waits here, then sees refunded = true.
    transaction.with_lock do
      # FIX #1: idempotency guard. Already refunded means nothing to do.
      next if transaction.refunded?

      response = GiftCardService.new(
        site: site,
        card_number: transaction.card_number,
        remote_transaction_id: remote_transaction_id
      ).undo

      # FIX #2: only an explicit "0" code counts as success (see undo_succeeded?).
      if undo_succeeded?(response)
        provider_confirmed = true

        # FIX #3: update! instead of update_column, so validations, callbacks
        # (auditing, balance sync, webhooks...) and updated_at all run.
        transaction.update!(refunded: true)

        # FIX #3: leave an audit trail of what the provider confirmed.
        logger.info(
          "[GiftCardUndoJob] refunded transaction_id=#{transaction.id} " \
          "remote_transaction_id=#{remote_transaction_id} " \
          "response_code=#{response['ResponseCode'].inspect}"
        )
      else
        retry_undo(site.id, transaction.id, remote_transaction_id)
      end
    end
  rescue => e
    # FIX #1: once the provider has confirmed the undo, a failure to save it
    # (DB failover, lock timeout, validation error) must not cause another undo.
    if provider_confirmed
      raise UndoNotRecordedError,
            "Provider confirmed undo for transaction_id=#{transaction.id} " \
            "remote_transaction_id=#{remote_transaction_id} but it was not " \
            "recorded: #{e.class}: #{e.message}"
    end

    retry_undo(site.id, transaction.id, remote_transaction_id)
  end

  # FIX #2: nil.to_i, "".to_i and "ERR".to_i are all 0, so the old check
  # marked missing, empty or garbled codes as refunded. Now the code must
  # be all zeros ("0", "00" or the integer 0). Anything else counts as
  # failure and is retried, which is the safe direction.
  def undo_succeeded?(response)
    response.respond_to?(:[]) && response["ResponseCode"].to_s.match?(/\A0+\z/)
  end

  def retry_undo(site_id, transaction_id, remote_transaction_id)
    GiftCardUndoJob.set(wait: 30.seconds).perform_later(site_id, transaction_id, remote_transaction_id)
  end
end
