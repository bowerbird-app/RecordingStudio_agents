# Recording Studio agents on the 6.1 layout

Hosts install this gem beside Recording Studio `~> 7.7` (tag `v7.7.2`) and Flatpack tag `v0.1.380`. Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations.

- Gemspec: `recording_studio` `~> 7.7`, `flat_pack` `>= 0.1.354`, `view_component` `>= 4.14`, `< 5`
- This repository locks `view_component` `~> 4.19`
- `config.layout` is `nil`, `false`, a layout name, or `->(controller:) { ... }`
- `nil` follows `RecordingStudio.configuration.layout`, then `recording_studio/default_layout`
- Page headings are `content_for :title` and `content_for :subtitle`
- Back and close use `flat_pack_page_nav`. Page actions use `register_page_nav`
- AI `~> 0.25` (tag `v0.25.3`), Metrics `v0.9.2`, and Logs `v0.8.2`. API is `>= 0.26.0, < 2.0` (dummy tag `v1.19.0`)
- Accessible `v0.55.0`, Trashable `v1.2.3`, Moveable `v6.0.3`, Admin `v2.19.1`, Users `v0.37.0`, and Root Switchable `v0.16.1` are the dummy tags. Cache `v0.7.1`, Attachable `v0.33.2`, Site Settings `v0.6.0`, and Icons `v0.4.2` are pinned in the dummy. MCP is `v0.39.2` and Oauth is `v0.25.1`. The dummy FlatPack pin is `v0.1.380`.
- The dummy sets `config.authorize_write` so Recording Studio allows `record!` when an actor is present
- Roots are created with `create_root_recording!(recordable, actor:)`. Seed lookups use `Recording.kept`. The dummy authorizer is `config.authorize_write`. Root Switchable still requires an Accessible `:view` grant on the current root for the mounted switch page
