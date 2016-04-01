class CreateProducts < ActiveRecord::Migration
  def change
    create_table :products do |t|
      t.string :reference
      t.integer :quantity

      t.timestamps
    end
  end
end
