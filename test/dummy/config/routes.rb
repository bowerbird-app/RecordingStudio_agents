Rails.application.routes.draw do
  devise_for :users

  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"
  mount RecordingStudioAgents::Engine, at: "/recording_studio_agents"
  mount RecordingStudioAI::Engine, at: "/recording_studio_ai"
  mount RecordingStudioAccessible::Engine, at: "/admin/access"
  recording_studio_admin_for :admin, at: "/admin", root_section: :agents

  get "up" => "rails/health#show", as: :rails_health_check

  post "agents/demo", to: "agents#create", as: :agents_demo

  root "home#index"
end
