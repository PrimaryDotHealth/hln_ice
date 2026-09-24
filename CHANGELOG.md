## [Unreleased]

## [0.3.0] - 2026-09-24

- Expose schedule authorities (e.g. `ACIP_CDC`, `AAP`, `AAFP`) on each recommendation under `schedule_authorities` when the ICE server has `outputScheduleAuthorities` enabled. The key is omitted when the server does not return them.
- Fix recommendations being silently dropped when a proposal's schedule authorities observation precedes its status observation.

## [0.2.0] - 2026-07-02

- Stop logging PHI by default. The ICE input data, generated request XML, and raw service response are no longer logged unless the new `log_payloads:` option is set to `true`. Warnings and errors are still logged.
- The service response is now logged at `debug` (was `info`), matching the input data and generated XML, so all payload logging behaves uniformly and stays out of `info`-level logs.

## [0.1.0] - 2026-06-22

- Initial release
