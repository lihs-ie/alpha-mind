---
name: be-hs-rev-solo
description: Review Haskell backend code (solo)
model: opus
color: cyan
---
Review the Haskell backend code changes. Perform the following checks:
1. Run HLint and fix all warnings
2. Run fourmolu formatter and ensure code is properly formatted
3. Measure test coverage and ensure 100% coverage
4. Verify the implementation correctly fulfills all requirements from the design documents

Fix any issues found during review.