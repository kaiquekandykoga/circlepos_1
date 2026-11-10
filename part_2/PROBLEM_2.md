# Part 2 - Backend Code Review and Safe Patch

Assess production-risk awareness, Rails debugging depth, and whether you can improve existing code without rewriting the world.

You do not need any CirclePOS knowledge for this task.

Read the Ruby background job below as if it came from an existing Rails application that is already running in production.

Identify the most important issues first, explain the likely production impact, and then show the smallest safe patch you would actually ship.

#### Snippet Under Review

Review the code below.

Assume a real team needs a safe correction, not a full rewrite.

```
class GiftCardUndoJob < ApplicationJob
    queue_as :normal_priority

    def perform(site_id, transaction_id, remote_transaction_id)
        transaction = GiftCardTransaction.find(transaction_id)
        site = Site.find(site_id)

        undo_transaction(site, transaction, remote_transaction_id)
    end

    private

    def undo_transaction(site, transaction, remote_transaction_id)
        response = GiftCardService.new(
            site: site,
            card_number: transaction.card_number,
            remote_transaction_id: remote_transaction_id
        ).undo

        if response["ResponseCode"].to_i.zero?
            transaction.update_column(:refunded, true)
        else
            retry_undo(site.id, transaction.id, remote_transaction_id)
        end
    rescue
        retry_undo(site.id, transaction.id, remote_transaction_id)
    end

    def retry_undo(site_id, transaction_id, remote_transaction_id)
        GiftCardUndoJob.set(wait: 30.seconds).perform_later(site_id, transaction_id, remote_transaction_id)
    end
end
```
