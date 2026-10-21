class CreatePressKits < ActiveRecord::Migration[8.1]
  def change
    create_table :press_kits, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.text :content

      t.timestamps
    end
  end
end
