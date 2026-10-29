# Set the agents page shell

Use this when a host screen should follow the Recording Studio default template, or when `config.layout` should pick a different shell.

## Set the layout

In `config/initializers/recording_studio_agents.rb`:

```ruby
RecordingStudioAgents.configure do |config|
  config.layout = nil
end
```

`nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`.

To force one layout for every agents screen:

```ruby
config.layout = "application"
```

To render with no layout:

```ruby
config.layout = false
```

To decide per request, pass a callable that takes `controller:` and returns a layout name, `nil`, or `false`:

```ruby
config.layout = ->(controller:) { controller.action_name == "show" ? "application" : nil }
```

A number, a blank string, or a callable with a positional parameter raises `ArgumentError`.

The ChatKit popup (`PopupsController#show`) always uses `recording_studio_agents/popup`. That shell is the document, the stylesheets, and the chat. It ignores `config.layout`, so a host nav does not wrap the iframe.

## Set the heading and the nav

The default layout draws one page title from the view. In the template:

```erb
<% content_for :title, "Agent chat" %>
<% content_for :subtitle, "Every chat in this workspace." %>
<% flat_pack_page_nav(round: true, style: :default, back_href: root_path, back_tooltip: "Home") %>
<% register_page_nav "Press kits", press_kits_path, role: :secondary %>
<% recording_studio_page_nav_right do %>
  <%= render FlatPack::Button::Component.new(text: "Sign out", style: :ghost, size: :md, type: "submit", form: "sign-out") %>
<% end %>
```

Leave the title out of the view body. A second `FlatPack::PageTitle` for that same heading would show a second `h1`.

The default layout calls `strip` on the title and subtitle. That drops HTML safety, and `PageTitle` escapes the string again. Pass the raw text with `html_safe` so an apostrophe is escaped once:

```erb
<% content_for :subtitle, kit.description.to_s.html_safe %>
```

`register_page_nav` takes `role: :primary`, `:secondary`, or `:destructive`. Put a workspace switcher or a form in `recording_studio_page_nav_right` when it is not a link.

## Cards

Pass `background:`, `border:`, and `shadow:` to `FlatPack::Card`. `background: :shaded` is the shaded fill. `background: :default` is the plain fill.
