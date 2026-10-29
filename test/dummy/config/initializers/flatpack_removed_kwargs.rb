# frozen_string_literal: true

# Root Switchable v0.9.7 still passes PageNav keywords and Card style that
# Flatpack 0.1.319 rejects. Our own views pass the current keywords.
module DummyPageNavClose
  def initialize(*args, anchor_url: nil, anchor_label: nil, **kwargs)
    super(*args, **kwargs)
    return if anchor_url.blank? && anchor_label.blank?
    return if anchor_url.blank?

    with_close(href: anchor_url, tooltip: anchor_label)
  end
end

module DummyCardWithoutStyle
  KNOWN_BACKGROUNDS = %i[default none shaded brand brand_subtle gradient].freeze

  def initialize(*args, style: nil, **kwargs)
    if style && !kwargs.key?(:background)
      background = style.to_sym
      kwargs[:background] = background if KNOWN_BACKGROUNDS.include?(background)
    end

    super(*args, **kwargs)
  end
end

Rails.application.config.to_prepare do
  page_nav = FlatPack::PageNav::Component
  page_nav.prepend(DummyPageNavClose) unless page_nav.ancestors.include?(DummyPageNavClose)

  card = FlatPack::Card::Component
  card.prepend(DummyCardWithoutStyle) unless card.ancestors.include?(DummyCardWithoutStyle)
end
