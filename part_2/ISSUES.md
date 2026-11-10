# Part 2 - Issues in `GiftCardUndoJob`

Issues are listed by production risk, highest first. Money-correctness problems come before operational ones, and operational ones come before style.

---

## 1. No idempotency guard, so the same undo can run twice against the provider

```ruby
def perform(site_id, transaction_id, remote_transaction_id)
  transaction = GiftCardTransaction.find(transaction_id)
  ...
  undo_transaction(site, transaction, remote_transaction_id)
```

`perform` never checks `transaction.refunded?` before it calls the provider. Several common paths send a second undo for a transaction that was already reversed:

- The provider applies the undo, but the response is lost (timeout, connection reset, parse error). The bare `rescue` catches it and re-enqueues, so the undo is sent again.
- The provider applies the undo and returns `0`, then `update_column` fails (DB failover, lock timeout). The `rescue` catches that too and re-enqueues. `refunded` is still `false`, so the next run sends the undo again.
- The job gets enqueued twice (a double-click, a caller retry, or the queue adapter redelivering after a worker crash). Both copies run, with no lock and no check.

**Impact:** Unless the provider's undo is guaranteed idempotent per `remote_transaction_id` (we can't assume it is), a card can be credited or reversed more than once. That is direct financial loss, and nobody notices until a reconciliation or a customer complaint turns it up.

---

## 2. A missing or garbled `ResponseCode` counts as success

```ruby
if response["ResponseCode"].to_i.zero?
  transaction.update_column(:refunded, true)
```

In Ruby, `nil.to_i == 0`, `"".to_i == 0` and `"ERR".to_i == 0`. Any of these marks the transaction as refunded:

- an error payload with a different shape (`{"Error" => "..."}`)
- an empty hash, or a body from a proxy or maintenance page
- a non-numeric code

**Impact:** The record says `refunded: true` but the provider never reversed anything. The customer loses money, and because the DB says the refund happened, support and reconciliation tools show nothing wrong. This is the hardest failure to detect.

---

## 3. Retries never stop

```ruby
else
  retry_undo(site.id, transaction.id, remote_transaction_id)
end
rescue
  retry_undo(site.id, transaction.id, remote_transaction_id)
```

Every non-zero response and every exception re-enqueues the job in 30 seconds, with no attempt counter and no limit. The job also treats every non-zero code as temporary. Permanent business failures will never succeed, yet they get retried forever. Examples:

- "already voided"
- "transaction not found"
- "card closed"
- invalid `remote_transaction_id`

**Impact:**

- Each permanently failing transaction becomes a job that runs every 30 seconds for good. That is 2,880 provider calls per day for each bad record.
- During a provider outage, every pending undo retries in lockstep on a fixed 30-second delay with no backoff or jitter. The surge can hit provider rate limits, get the merchant account throttled or locked, and slow the recovery.
- The jobs pile up in `normal_priority` and delay unrelated work on that queue.
- There is no point where a human gets told "this refund cannot complete".

---

## 4. The bare `rescue` hides every failure, bugs included

```ruby
rescue
  retry_undo(...)
```

A bare `rescue` catches all `StandardError`s. That includes programming errors (`NoMethodError` when `response` is `nil`, `TypeError`, `ArgumentError` from a changed `GiftCardService` signature), DB errors, and enqueue errors. Nothing gets logged or sent to error tracking, and the job always finishes "successfully" from the adapter's point of view.

**Impact:**

- A deploy that breaks `GiftCardService` turns every undo into a silent loop that retries forever (see #3). No alert fires.
- The adapter's own safety nets are bypassed: retry counts, exponential backoff, the dead/morgue set, and failure dashboards.
- On-call has nothing to debug with: no exception, no log line, no record of which transaction failed or why.

---

## 5. Missing records are handled inconsistently

```ruby
transaction = GiftCardTransaction.find(transaction_id)
site = Site.find(site_id)
```

Both `find` calls run in `perform`, outside the `rescue`. A deleted or never-committed record raises `ActiveRecord::RecordNotFound`, which goes to the adapter's default retry policy. That is the opposite of how failures inside `undo_transaction` are handled. If the job is enqueued inside a DB transaction that hasn't committed yet (enqueue before commit), the first run fails for no real reason.

**Impact:** A permanently missing record produces noisy adapter retries and dead jobs. A not-yet-committed record causes a pointless failure plus a delay. The two error paths behave differently, which makes production behavior harder to reason about.

---

## 6. `update_column` skips callbacks, validations and `updated_at`

```ruby
transaction.update_column(:refunded, true)
```

`update_column` writes one column with raw SQL. Model callbacks don't run, which may mean skipping auditing, balance sync, webhooks or cache invalidation. `updated_at` doesn't change either, and nothing records when the refund was confirmed or what the provider returned.

**Impact:** Any downstream logic tied to the model lifecycle never sees the refund. The audit trail says nothing about when or how the undo was confirmed, which matters for gift-card disputes and financial reconciliation.

---

## 7. Lower-priority items

- **The site and the transaction aren't checked against each other.** `site_id` and `transaction_id` are passed separately, and nothing confirms the transaction belongs to the site. If a caller passes the wrong pair, the undo goes to the wrong site's provider credentials.
- **The retry is hand-rolled instead of using `retry_on`.** `GiftCardUndoJob.set(wait:).perform_later` starts a brand-new job each time, so `executions` resets and attempt history is lost. ActiveJob's `retry_on` / `discard_on` already give bounded, backed-off, observable retries.
- **`retry_undo` can raise inside the `rescue`.** If the enqueue fails in the `else` branch (Redis or DB queue down), the `rescue` calls `retry_undo` again. That fails the same way, and the second exception escapes without context.
- **Style.** The code uses 4-space indentation instead of the usual Ruby 2-space style. It's cosmetic, but it adds noise to diffs in an existing codebase.
