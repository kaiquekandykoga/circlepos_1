## Triage Plan

Understanding the problem and its root cause is always the first step. Normally, I examine logs, observability tools, and available data. In some cases, I rely on screenshots provided by the operations team or other relevant artifacts to assist with triaging. If I am faced with partial logs and incomplete context, I typically need to simulate the issue in a local or test environment to pinpoint the root cause before implementing a fix. I'd hold off on creating a fix until I can replicate the issue that way, I can be more confident in what's causing it

## Risks and Unknowns

Replicating a production environment locally or in staging isn't always viable. Even if I can reproduce the issue, there's a risk the patch won't fully resolve it in prod. In those cases, wrapping the fix in a feature flag for quick rollback is crucial
