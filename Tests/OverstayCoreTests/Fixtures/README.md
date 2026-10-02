# Fixtures

Classifier fixtures live here as JSON: an array of `ProcessSnapshot` plus the expected tier per pid (`docs/BUILD_PLAN.md`
§6.1). Tests read them with `#filePath`, not as bundled resources, so Linux builds stay warning-free.

Real dumps from testers (T2) go here after redaction: `argv` already scrubbed by `Scrub`, no environment values, no
personal paths (CI fails on home paths).
