## [Unreleased]

## [0.5.0] - 2026-10-13

- **Fix recommendations getting the wrong status when the ICE server outputs series information** (`ICE_OUTPUTSERIESINFORMATION`). The parser took the first coded observation anywhere in a proposal, which could be the selected series instead of the status. When it was, the recommendation's `status` was a series code (e.g. `HEP_B_ADULT_3_DOSE_SERIES`) and its `reasons` were empty, so `simplified_status` reported that vaccine group as `"overdue"` whatever ICE recommended. ICE orders these blocks differently from one request to the next, so which vaccine groups were affected varied. Upgrade before turning series output on.
- Read every value from the observation it belongs to, by its `observationFocus` code system and code, instead of by position or with descendant searches. This applies to recommendation status and reasons, schedule authorities, dose evaluation status, and the patient and proposal elements. Responses from servers without series output parse exactly as before.
- Expose the series ICE selected for each recommendation under `series` (`code`, `name`, and `selection`: `"unambiguous"`, `"best_guess"`, or `"alternative"`), its `season` for seasonal vaccines (`code`, `name`, `starts_on`, and `ends_on`), and `doses_remaining` when the server has `ICE_OUTPUTNUMBEROFDOSESREMAINING` enabled. `doses_remaining` is an Integer for a plain count and ICE's text otherwise (e.g. `"Recurring"`). Each evaluation gets the `series` the dose was evaluated against. All new keys are left out when ICE does not send them.
- Season `starts_on` and `ends_on` are ISO dates read from the trailing `(MM/DD/YYYY - MM/DD/YYYY)` of ICE's season display name, because ICE sends no structured season dates. Both are `nil` if the name does not end in a valid range, e.g. if ICE changes that format. They are passed through as ICE sends them: an `ends_on` of `2100-01-01` is ICE's open-ended end date, and for a season newer than its newest coded one, ICE returns that code and label with the actual season's dates (for influenza, `20152016_INFLUENZA_SEASON`, the newest in ICE's `supportedSeasons.yml`). Rely on the dates, not the code.

## [0.4.0] - 2026-10-06

- Expose ICE's per-dose evaluations under `evaluations` in the result, with one entry per administered dose and vaccine group it counts toward (so a combination vaccine has several). Each entry has the caller's event id, CVX, administration date, vaccine group, dose number, validity, evaluation status, and reasons. Codes are passed through as ICE returns them. `recommendations` and `simplified_status` are unchanged.

## [0.3.0] - 2026-09-24

- Expose schedule authorities (e.g. `ACIP_CDC`, `AAP`, `AAFP`) on each recommendation under `schedule_authorities` when the ICE server has `outputScheduleAuthorities` enabled. The key is omitted when the server does not return them.
- Fix recommendations being silently dropped when a proposal's schedule authorities observation precedes its status observation.

## [0.2.0] - 2026-07-02

- Stop logging PHI by default. The ICE input data, generated request XML, and raw service response are no longer logged unless the new `log_payloads:` option is set to `true`. Warnings and errors are still logged.
- The service response is now logged at `debug` (was `info`), matching the input data and generated XML, so all payload logging behaves uniformly and stays out of `info`-level logs.

## [0.1.0] - 2026-06-22

- Initial release
