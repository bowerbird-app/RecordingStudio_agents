module ApplicationHelper
  def press_kit_slides(images)
    images.filter_map do |image|
      attachment = image.recordable
      next unless attachment.file.attached?

      {
        type: :image,
        src: press_kit_image_url(image, attachment),
        alt: attachment.alt_text.presence || attachment.name,
        caption: attachment.alt_text.presence || attachment.name
      }
    end
  end

  def press_kit_image_url(image, attachment)
    if attachment.preview_target_named(:med)
      attachment.url_for_variant(
        :med,
        rails_url: recording_studio_attachable.attachment_preview_file_path(image, variant_name: :med)
      )
    else
      attachment.original_url(
        rails_url: recording_studio_attachable.attachment_file_path(image)
      )
    end
  end

  def dummy_page_nav(title:, back_url: nil, back_label: "Home")
    recording_studio_page_nav(
      title: title,
      page_nav_back_url: back_url,
      page_nav_back_label: back_label
    )

    recording_studio_page_nav_right do
      concat tag.div(class: "hidden items-center gap-2 lg:flex") { safe_join(press_kit_nav_actions) }
      concat tag.div(class: "flex min-w-0 items-center gap-2 lg:hidden") {
        safe_join([
          recording_studio_root_switch_dropdown(
            style: :ghost,
            size: :md,
            trigger_attributes: { class: "whitespace-nowrap" }
          ),
          press_kit_nav_menu
        ])
      }
    end
  end

  private

  def press_kit_nav_actions
    [
      render(FlatPack::Button::Component.new(
        text: "Press kits",
        style: :ghost,
        size: :md,
        href: main_app.press_kits_path
      )),
      render(FlatPack::Button::Component.new(
        text: "Agent chat",
        style: :ghost,
        size: :md,
        href: main_app.agent_chat_path
      )),
      recording_studio_root_switch_dropdown(style: :ghost, size: :md),
      render(FlatPack::Button::Component.new(
        text: "Sign out",
        style: :ghost,
        size: :md,
        href: main_app.destroy_user_session_path,
        method: :delete
      ))
    ]
  end

  def press_kit_nav_menu
    render(FlatPack::Button::Dropdown::Component.new(
      text: "Menu",
      style: :ghost,
      size: :md,
      placement: :bottom_right,
      trigger_attributes: { aria: { label: "Open the menu" } }
    )) do |dropdown|
      dropdown.menu_item(text: "Press kits", href: main_app.press_kits_path)
      dropdown.menu_item(text: "Agent chat", href: main_app.agent_chat_path)
      dropdown.menu_item(
        text: "Sign out",
        href: main_app.destroy_user_session_path,
        data: { turbo_method: :delete }
      )
    end
  end
end
