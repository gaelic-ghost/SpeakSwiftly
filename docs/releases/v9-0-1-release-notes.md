# v9.0.1 Release Notes

## What Changed

- Added focused worker-protocol coverage for preserving
  `request_context.prefacePolicy` through live speech and retained-file
  generation request decoding.
- Added the quick SpeakSwiftly E2E suite to the standard release script so patch
  and release-candidate branches run generated-file coverage before PR creation.

## Breaking Changes

None.

## Migration Notes

No caller changes are required.

## Verification

- `swift test --filter WorkerProtocolTests`
- `sh scripts/repo-maintenance/run-e2e.sh --suite quick`
- Standard release validation runs `sh scripts/repo-maintenance/validate-all.sh`
  and the quick E2E suite before pushing the release branch.
