# HlnIce

A Ruby client for the [HLN ICE](https://www.hln.com/ice/) (Immunization Calculation Engine), an OpenCDS clinical decision-support service for immunization forecasting.

Given a patient's demographics and immunization history, `HlnIce` builds the
VMR (Virtual Medical Record) request, calls the ICE evaluation endpoint, and
parses the response into:

- a full list of **recommendations** (one per vaccine group, with status, reasons, and administration intervals), and
- a **simplified status** map keyed by vaccine group — e.g. `{ ipv_opv: "overdue", mmr: "compliant" }`.

The gem has no Rails or ActiveSupport dependency; it takes an injected logger
so it can run in any Ruby application.

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "hln_ice"
```

Then run:

```sh
bundle install
```

Or install it directly:

```sh
gem install hln_ice
```

## Usage

### Creating a client

```ruby
client = HlnIce::Client.new(base_url: "https://ice.example.com")
```

All options:

| Option        | Default                  | Description                                           |
| ------------- | ------------------------ | ----------------------------------------------------- |
| `base_url:`   | _(required)_             | Base URL of the ICE OpenCDS service.                  |
| `timeout:`    | `30`                     | HTTP request timeout, in seconds.                     |
| `max_retries:`| `3`                      | Number of retries on a failed evaluation request.     |
| `retry_delay:`| `1`                      | Seconds to wait between retries.                      |
| `logger:`     | `Logger.new($stdout)`    | Any `Logger`-compatible object. In Rails, pass `Rails.logger`. |
| `log_payloads:`| `false`                 | When `true`, logs the ICE input data, generated request XML, and raw service response. These contain patient PHI, so keep this off outside local debugging. |

```ruby
# In a Rails app, reuse the application logger:
client = HlnIce::Client.new(base_url: ENV["ICE_URL"], logger: Rails.logger)
```

### Checking availability

```ruby
client.available? # => true / false
```

### Evaluating immunizations

Pass a patient hash with their demographics and (optionally) prior
immunization events:

```ruby
patient_data = {
  patient: {
    id: "12345",
    date_of_birth: "2020-01-01", # parseable date string
    gender: "M"                  # "M", "F", or blank (defaults to "U")
  },
  immunizations: [
    {
      clinicalStatements: {
        substanceAdministrationEvents: [
          {
            substance: {
              substanceCode: { code: "10", displayName: "Polio" }
            },
            administrationTimeInterval: { low: "2020-03-01", high: "2020-03-01" }
          }
        ]
      }
    }
  ]
}

result = client.evaluate_immunizations(patient_data)
```

### The result

On success:

```ruby
{
  success: true,
  data: {
    raw_xml: "<...the decoded ICE response XML...>",
    patient: { id: "12345", birth_date: "2020-01-01", gender: "M" },
    recommendations: [
      {
        vaccine: { code: "10", code_system: "...", name: "Polio Vaccine Group" },
        status:  { code: "RECOMMENDED", name: "Recommended" },
        reasons: [{ code: "DUE_NOW", name: "Due Now" }],
        intervals: { proposed: { low: "2020-03-01", high: "2020-04-01" } },
        # Only present when the ICE server has outputScheduleAuthorities enabled
        schedule_authorities: [
          { code: "ACIP_CDC", name: "Advisory Committee on Immunization Practices / Centers for Disease Control and Prevention" },
          { code: "AAP", name: "American Academy of Pediatrics" }
        ]
      }
    ],
    simplified_status: { ipv_opv: "overdue" }
  }
}
```

On failure (service error, timeout after retries, or unparseable response):

```ruby
{ success: false, error: "ICE service error: 400 - ..." }
```

Always branch on `result[:success]` before reading `result[:data]`.

### Simplified status values

`simplified_status` maps each recognized vaccine group to one of:

| Value              | Meaning                                                     |
| ------------------ | ----------------------------------------------------------- |
| `"compliant"`      | Up to date (ICE `FUTURE_RECOMMENDED` / `NOT_RECOMMENDED`).  |
| `"overdue"`        | A dose is recommended now (ICE `RECOMMENDED`).              |
| `"conditional"`    | Conditionally recommended (ICE `CONDITIONAL`).             |
| `"medically_exempt"` | Conditional status with a medical-exemption reason.       |

The recognized vaccine-group keys are: `:dtap_tdap`, `:hep_a`, `:hep_b`,
`:hib`, `:hpv`, `:mcv4`, `:mmr`, `:pcv`, `:ipv_opv`, and `:var`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then,
run `rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/PrimaryDotHealth/hln_ice.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
