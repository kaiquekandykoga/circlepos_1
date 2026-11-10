# Part 2 - Issues in `GiftCardUndoJob`

Ordered by production risk: money correctness first, then operations, then style.

---

## 1. No idempotency guard, so the same undo can run twice

`perform` never checks `transaction.refunded?` before calling the provider. A second undo gets sent when:

- the provider applies the undo but the response is lost (timeout, reset, parse error), and the bare `rescue` re-enqueues;
- the provider returns `0` but `update_column` fails (failover, lock timeout), so `refunded` stays `false` and the retry sends it again;
- the job is enqueued twice (double-click, caller retry, redelivery after a worker crash), with no lock or check.

**Impact:** Unless the provider's undo is idempotent per `remote_transaction_id` (we can't assume it is), a card can be reversed more than once. That is direct financial loss, found only at reconciliation or through a complaint.

---

## 2. A missing or garbled `ResponseCode` counts as success

```ruby
if response["ResponseCode"].to_i.zero?
```

`nil.to_i`, `"".to_i` and `"ERR".to_i` are all `0`. An error payload with a different shape, an empty hash, a proxy/maintenance page body or a non-numeric code all mark the transaction refunded.

**Impact:** The DB says `refunded: true` but nothing was reversed. The customer loses money and every tool shows the refund as done. This is the hardest failure to detect.

---

## 3. Retries never stop

Every non-zero response and every exception re-enqueues in 30 seconds, with no attempt limit. Permanent failures ("already voided", "not found", "card closed", bad `remote_transaction_id`) are treated as temporary.

**Impact:**

- Each permanently failing record makes 2,880 provider calls a day, forever.
- In a provider outage, all pending undos retry in lockstep with no backoff or jitter, risking rate limits, account lockout and slower recovery.
- Jobs pile up in `normal_priority` and delay unrelated work.
- No human is ever told a refund cannot complete.

---

## 4. The bare `rescue` hides every failure, bugs included

`rescue` catches all `StandardError`s: programming errors (`NoMethodError` on a `nil` response, an `ArgumentError` from a changed `GiftCardService` signature), DB errors and enqueue errors. Nothing is logged or reported, and the job always "succeeds".

**Impact:** A deploy that breaks `GiftCardService` turns every undo into a silent infinite loop (see #3). The adapter's retry counts, backoff, dead set and dashboards are bypassed, and on-call has nothing to debug with.

---

## 5. Missing records are handled inconsistently

Both `find` calls sit outside the `rescue`, so `RecordNotFound` goes to the adapter's default retry policy, unlike every other failure. If the job is enqueued before the surrounding DB transaction commits, the first run fails for no real reason.

**Impact:** Noisy retries and dead jobs for deleted records, pointless delays for uncommitted ones, and two error paths that behave differently.

---

## 6. `update_column` skips callbacks, validations and `updated_at`

Callbacks (auditing, balance sync, webhooks, cache invalidation) don't run, `updated_at` doesn't change, and nothing records when the refund was confirmed or what the provider returned.

**Impact:** Downstream logic never sees the refund, and the audit trail is empty exactly where disputes and reconciliation need it.

---

## 7. Lower-priority items

- **Site and transaction aren't cross-checked.** A wrong `site_id` sends the undo with another site's provider credentials.
- **Hand-rolled retry instead of `retry_on`.** Each `set(wait:).perform_later` starts a fresh job, so `executions` and attempt history are lost. `retry_on` / `discard_on` already give bounded, backed-off, observable retries.
- **`retry_undo` can raise inside the `rescue`.** If enqueueing fails (Redis or queue DB down), the `rescue` calls it again, which fails the same way and escapes without context.
- **Style.** 4-space indentation instead of Ruby's usual 2, which adds diff noise.
