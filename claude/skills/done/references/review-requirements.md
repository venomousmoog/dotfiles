# Personal Review Requirements

Applied to every commit before submission. Edit this file to add your own criteria.

## Requirements

1. **E2E Test Coverage**: Changes should be covered by an E2E test with minimal mocking that exercises code paths close to what is deployed. For new functionality, look for existing E2E test patterns in the same directory and add coverage. For modifications, verify existing E2E tests still cover the change. If no E2E test exists and the change is non-trivial, flag this to the user.

2. **No Test-Only Production Code**: Don't add test-only methods, flags, or conditional paths to production code. Tests should exercise real code paths.

## How to Add Requirements

Add numbered items above. Each should describe:
- **What** to check
- **What "good" looks like** so Claude can evaluate it
- **When to skip** (if ever)
