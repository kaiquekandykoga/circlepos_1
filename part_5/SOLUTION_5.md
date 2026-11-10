# Architecture Notes

For new projects, I prefer sticking to Ruby on Rails conventions to help new developers get up to speed quickly. For existing projects, however, I take the time to understand the current architecture and adapt to it when building new features.

When it comes to naming, I like using common business terminology to bridge communication between developers and product teams. Having lived through my share of production incidents, I know how vital clear logs are for debugging, so I always put thought into placing them strategically.

In large codebases, I avoid putting callbacks in heavily accessed models to protect database performance. I also make sure background jobs are idempotent, preventing data issues if retries are triggered.

While writing unit tests is non-negotiable, I weigh the high effort of E2E tests against a feature's criticality before deciding to write them. Finally, I keep parameter validation at the endpoint level and reserve business logic validation for the models.
