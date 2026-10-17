# frozen_string_literal: true

RecordingStudioAgents::Engine.routes.draw do
  post "chatkit", to: "chatkit#create"
  root "home#index"
end
