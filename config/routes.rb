# frozen_string_literal: true

RecordingStudioAgents::Engine.routes.draw do
  root "home#index"

  namespace :admin do
    post "agents/:agent_key/turn_on", to: "agents#turn_on", as: :turn_on_agent
    post "agents/:agent_key/turn_off", to: "agents#turn_off", as: :turn_off_agent
  end
end
