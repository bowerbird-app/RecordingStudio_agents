# Recording Studio agents on the 6.1 layout

Hosts install this gem beside Recording Studio `v6.1.0` and Flatpack `0.1.319` (commit `1fcbafe94f8eb118f0a22182f63f5110fcc97a56`).

- Gemspec: `recording_studio` `>= 6.1.0`, `flat_pack` `>= 0.1.315`, `view_component` `>= 4.14`, `< 5`
- This repository locks `view_component` `4.19.0`
- `config.layout` is `nil`, `false`, a layout name, or `->(controller:) { ... }`
- `nil` follows `RecordingStudio.configuration.layout`, then `recording_studio/default_layout`
- Page headings are `content_for :title` and `content_for :subtitle`
- Back and close use `flat_pack_page_nav`. Page actions use `register_page_nav`
- AI `~> 0.19.0`, with dummy pins AI `v0.19.1`, Metrics `v0.7.0`, and Logs `v0.7.1`. Those three allow Recording Studio 6. Trashable `v0.11.3`, Users `v0.25.2`, Root Switchable `v0.9.7`, and Attachable `v0.20.2` still reject it, so both Gemfiles load `test/support/widen_recording_studio_requirement.rb`. That file is not shipped in the gem
- Site Settings `v0.5.1` still includes `UsesDefaultLayout`. The dummy defines an empty module
- Root Switchable `v0.9.7` still passes removed Flatpack keywords. The dummy maps them in `config/initializers/flatpack_removed_kwargs.rb`
