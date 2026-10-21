# frozen_string_literal: true

class AddSlugAndSectionsToPressKits < ActiveRecord::Migration[8.1]
  def change
    change_table :press_kits, bulk: true do |t|
      t.string :slug
      t.jsonb :sections, null: false, default: []
    end
    # Slug repeats across workspaces. Both seeded roots use hello-house, so a unique index is not safe.
  end
end
