# frozen_string_literal: true

RecordingStudioAgents::Engine.routes.draw do
  get "popup", to: "popups#show", as: :popup
  post "chatkit", to: "chatkit#create"
end
