# frozen_string_literal: true

class AddSlugAndSectionsToPressKits < ActiveRecord::Migration[8.1]
  def change
    change_table :press_kits, bulk: true do |t|
      t.string :slug
      t.jsonb :sections, null: false, default: []
    end
  end
end
