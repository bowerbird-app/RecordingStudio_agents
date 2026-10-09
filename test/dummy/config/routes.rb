Rails.application.routes.draw do
  devise_for :users

  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"
  mount RecordingStudioAgents::Engine, at: "/recording_studio_agents"
  mount RecordingStudioAI::Engine, at: "/recording_studio_ai"
  mount RecordingStudio::WebSearch::Engine, at: "/addons/recording"
  mount RecordingStudioAccessible::Engine, at: "/admin/access"
  recording_studio_admin_for :admin, at: "/admin", root_section: :root

  get "up" => "rails/health#show", as: :rails_health_check

  post "agents/demo", to: "agents#create", as: :agents_demo
  get "playground", to: "playground#new", as: :playground
  post "playground", to: "playground#create"
  get "playground/runs/:idempotency_key",
    to: "playground#show",
    as: :playground_run,
    constraints: { idempotency_key: /playground:[0-9a-f-]+/ }

  root "home#index"
end
