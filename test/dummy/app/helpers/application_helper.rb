module ApplicationHelper
  def press_kit_slides(images)
    images.filter_map do |image|
      file = image.recordable.file
      next unless file.attached?

      {
        type: :image,
        src: url_for(file),
        alt: image.recordable.alt_text.presence || image.recordable.name,
        caption: image.recordable.name
      }
    end
  end

  def dummy_page_nav(title:, back_url: nil, back_label: "Home")
    recording_studio_page_nav(
      title: title,
      page_nav_back_url: back_url,
      page_nav_back_label: back_label
    )

    recording_studio_page_nav_right do
      concat render(
        FlatPack::Button::Component.new(
          text: "Press kits",
          style: :ghost,
          size: :md,
          href: main_app.press_kits_path
        )
      )
      concat render(
        FlatPack::Button::Component.new(
          text: "Agent chat",
          style: :ghost,
          size: :md,
          href: main_app.agent_chat_path
        )
      )
      concat recording_studio_root_switch_dropdown(style: :ghost, size: :md)
      concat render(
        FlatPack::Button::Component.new(
          text: "Sign out",
          style: :ghost,
          size: :md,
          url: main_app.destroy_user_session_path,
          data: { turbo_method: :delete }
        )
      )
    end
  end
end
