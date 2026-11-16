# Recording Studio agents on the 6.1 layout

Hosts install this gem beside Recording Studio `v7.0.0` and Flatpack tag `v0.1.356`.

- Gemspec: `recording_studio` `>= 7.0.0`, `< 8.0`, `flat_pack` `>= 0.1.354`, `view_component` `>= 4.14`, `< 5`
- This repository locks `view_component` `4.19.0`
- `config.layout` is `nil`, `false`, a layout name, or `->(controller:) { ... }`
- `nil` follows `RecordingStudio.configuration.layout`, then `recording_studio/default_layout`
- Page headings are `content_for :title` and `content_for :subtitle`
- Back and close use `flat_pack_page_nav`. Page actions use `register_page_nav`
- AI `>= 0.22.0, < 2.0`, with dummy pins AI `v0.22.0`, Metrics `v0.9.0`, and Logs `v0.8.0`. API is `>= 0.26.0, < 2.0` (dummy tag `v0.26.0`)
- Accessible `v0.44.0`, Trashable `v0.17.0`, Moveable `v5.0.0`, Admin `v2.16.0`, Users `v0.30.0`, and Root Switchable `v0.16.0` are the core 7 tags. Cache `v0.6.3`, Attachable `v0.28.0`, Site Settings `v0.5.6`, and Icons `v0.2.1` stay. MCP is `v0.33.3` and Oauth is `v0.21.9` so the dummy can resolve core 7. The dummy FlatPack pin is `v0.1.376`.
- The dummy sets `config.authorize_write` so Recording Studio allows `record!` when an actor is present
- Roots are created with `create_root_recording!(recordable, actor:)`. Seed lookups use `Recording.kept`. The dummy authorizer is `config.authorize_write`. Root Switchable still requires an Accessible `:view` grant on the current root for the mounted switch page
