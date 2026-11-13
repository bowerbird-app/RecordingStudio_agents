# Recording Studio agents on the 6.1 layout

Hosts install this gem beside Recording Studio `v6.7.0` and Flatpack tag `v0.1.356`.

- Gemspec: `recording_studio` `~> 6.0`, `>= 6.1.0`, `flat_pack` `>= 0.1.354`, `view_component` `>= 4.14`, `< 5`
- This repository locks `view_component` `4.19.0`
- `config.layout` is `nil`, `false`, a layout name, or `->(controller:) { ... }`
- `nil` follows `RecordingStudio.configuration.layout`, then `recording_studio/default_layout`
- Page headings are `content_for :title` and `content_for :subtitle`
- Back and close use `flat_pack_page_nav`. Page actions use `register_page_nav`
- AI `>= 0.21.2, < 1.0`, with dummy pins AI `v0.21.2`, Metrics `v0.8.0`, and Logs `v0.7.4`. API is `~> 0.23.0` (dummy tag `v0.23.0`)
- Accessible `v0.32.0`, Trashable `v0.14.0`, Cache `v0.6.3`, Attachable `v0.23.0`, Site Settings `v0.5.6`, and Icons `v0.2.1` accept Recording Studio 6. The Gemfiles pin those tags
- The dummy sets `config.authorize_write` so Recording Studio 6.5 allows `record!` when an actor is present
- Trashable `v0.14.0` adds `purge_at`. Root Switchable `v0.15.0` requires an Accessible `:view` grant on the current root for the mounted switch page
