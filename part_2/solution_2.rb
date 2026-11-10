class GiftCardUndoJob < ApplicationJob
  queue_as :normal_priority

  # FIX #1: provider undid the card but we couldn't save it. Don't retry.
  class UndoNotRecordedError < StandardError; end
  discard_on UndoNotRecordedError

  def perform(site_id, transaction_id, remote_transaction_id)
    transaction = GiftCardTransaction.find(transaction_id)
    site = Site.find(site_id)

    undo_transaction(site, transaction, remote_transaction_id)
  end

  private

  def undo_transaction(site, transaction, remote_transaction_id)
    undone = false

    # FIX #1: lock and reload the row so only one job can undo it.
    transaction.with_lock do
      next if transaction.refunded?

      response = GiftCardService.new(
        site: site,
        card_number: transaction.card_number,
        remote_transaction_id: remote_transaction_id
      ).undo

      # FIX #2: only an explicit zero code is success.
      if response["ResponseCode"].to_s.match?(/\A0+\z/)
        undone = true
        # FIX #3: update! runs validations, callbacks and updated_at.
        transaction.update!(refunded: true)
      else
        retry_undo(site.id, transaction.id, remote_transaction_id)
      end
    end
  rescue => e
    # FIX #1: never resend an undo the provider already confirmed.
    raise UndoNotRecordedError, "transaction #{transaction.id}: #{e.message}" if undone

    retry_undo(site.id, transaction.id, remote_transaction_id)
  end

  def retry_undo(site_id, transaction_id, remote_transaction_id)
    GiftCardUndoJob.set(wait: 30.seconds).perform_later(site_id, transaction_id, remote_transaction_id)
  end
end
