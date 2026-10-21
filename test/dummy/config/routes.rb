Rails.application.routes.draw do
  devise_for :users, skip: %i[sessions registrations passwords]
  recording_studio_user_auth_for :users

  # RecordingStudio engine is data/API-focused and has no browser root route.
  # Keep legacy links working by redirecting the base path to the app home.
  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioAgents::Engine, at: "/recording_studio_agents"
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"
  mount RecordingStudioUser::Engine, at: "/account", as: :recording_studio_users
  mount RecordingStudioApi::Engine, at: "/recording_studio_api"
  mount RecordingStudioOauth::Engine, at: "/recording_studio_oauth"
  mount RecordingStudioMcp::Engine, at: "/recording_studio_mcp"
  mount RecordingStudioSiteSettings::Engine, at: "/recording_studio_site_settings"

  get "/.well-known/oauth-authorization-server",
      to: "recording_studio_oauth/oauth_discoveries#authorization_server",
      defaults: { api_key: "public" }
  RecordingStudioMcp.draw_named_api_well_known(self)
  RecordingStudioOauth::ProtectedResourceRegistry.draw_origin_well_known(self)

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "docs/install", to: "docs#install", as: :docs_install
  get "docs/config", to: "docs#configuration", as: :docs_config
  get "docs/recordable_types", to: "docs#recordable_types", as: :docs_recordable_types
  get "docs/recordings_tree", to: "docs#recordings_tree", as: :docs_recordings_tree
  get "docs/gem_views", to: "docs#gem_views", as: :docs_gem_views
  get "docs/methods", to: "docs#methods", as: :docs_methods

  # Defines the root path route ("/")
  get "agent-chat", to: "agent_chats#show", as: :agent_chat
  get "agent-chat/page", to: "agent_chats#page", as: :page_agent_chat
  resources :press_kits, only: %i[index show]
  root "home#index"
end
