# frozen_string_literal: true

class MenuPage
  Entry = Data.define(:name, :path, :icon, :match) do
    def active?(request)
      return request.path == path if match == :exact

      request.path.start_with?(path)
    end
  end

  def self.all
    helpers = Rails.application.routes.url_helpers
    admin = helpers.recording_studio_admin_admin_path
    [
      Entry.new(name: "Home", path: helpers.root_path, icon: :home, match: :exact),
      Entry.new(name: "Playground", path: helpers.playground_path, icon: :play, match: :prefix),
      Entry.new(name: "Staff", path: admin, icon: :building_office, match: :exact),
      Entry.new(name: "Agents", path: "#{admin}/sections/agents", icon: :sparkles, match: :prefix)
    ]
  end

  def self.find_by_name(name)
    wanted = name.to_s.strip.downcase
    return if wanted.blank?

    all.find { |entry| entry.name.downcase == wanted }
  end
end
