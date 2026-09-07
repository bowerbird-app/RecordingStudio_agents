# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `~> 4.2` (dummy GitHub tag `v4.2.0`)
- Recording Studio AI `~> 0.3` (dummy tag `v0.3.1`)
- Recording Studio Admin `~> 2.0` (dummy tag `v2.0.2`)
- Accessible `~> 0.6` (dummy tag `v0.7.0`)
- Root Switchable dummy tag `v0.5.0`
- FlatPack dummy tag `v0.1.143`

## Verification

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```

Run the dummy app from its directory:

```bash
cd test/dummy
bin/dev
```
