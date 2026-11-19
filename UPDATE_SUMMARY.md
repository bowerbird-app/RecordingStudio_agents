# Recording Studio agents on the 6.1 layout

Hosts install this gem beside Recording Studio `~> 7.8` (tag `v7.8.0`) and FlatPack `~> 0.2` (tag `v0.2.0`). Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations. Hosts moving to FlatPack 0.2 remove the manual `flat_pack/heroicons` importmap pin and any `flat-pack--icon` controller registration.

- Gemspec: `recording_studio` `~> 7.7`, `recording_studio_ai` `~> 0.25`, `flat_pack` `>= 0.1.354`, `view_component` `>= 4.14`, `< 5`
- This repository locks `view_component` `~> 4.19`
- `config.layout` is `nil`, `false`, a layout name, or `->(controller:) { ... }`
- `nil` follows `RecordingStudio.configuration.layout`, then `recording_studio/default_layout`
- Page headings are `content_for :title` and `content_for :subtitle`
- Back and close use `flat_pack_page_nav`. Page actions use `register_page_nav`
- AI gemspec `~> 0.25`. This repository pins `~> 0.26` (tag `v0.26.0`). Metrics `v0.10.0` and Logs `v0.9.0`. API is `>= 0.26.0, < 2.0` (dummy `~> 1.21`, tag `v1.21.2`)
- Accessible `v0.58.0`, Trashable `v1.3.0`, Moveable `v6.1.0`, Admin `v2.20.0`, Users `v0.37.0`, and Root Switchable `v0.17.0` are the dummy tags. Cache `v0.8.0`, Attachable `v0.34.0`, Site Settings `v0.6.0`, and Icons `v0.5.0` are pinned in the dummy. MCP is `v0.39.2` and Oauth is `v0.25.1`. The dummy FlatPack pin is `~> 0.2` (tag `v0.2.0`).
- The dummy sets `config.authorize_write` so Recording Studio allows `record!` when an actor is present
- Roots are created with `create_root_recording!(recordable, actor:)`. Seed lookups use `Recording.kept`. The dummy authorizer is `config.authorize_write`. Root Switchable still requires an Accessible `:view` grant on the current root for the mounted switch page
