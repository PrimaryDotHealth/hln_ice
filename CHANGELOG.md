## [Unreleased]

## [0.2.0] - 2026-07-02

- Stop logging PHI by default. The ICE input data, generated request XML, and raw service response are no longer logged unless the new `log_payloads:` option is set to `true`. Warnings and errors are still logged.
- The service response is now logged at `debug` (was `info`), matching the input data and generated XML, so all payload logging behaves uniformly and stays out of `info`-level logs.

## [0.1.0] - 2026-06-22

- Initial release
