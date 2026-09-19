class CreateDepartments < ActiveRecord::Migration[7.1]
  def change
    create_table :departments do |t|
      t.string :name, null: false

      t.timestamps
    end

    # Department is a reporting dimension: "payroll cost by department" is only
    # meaningful if the name is canonical, so uniqueness is enforced here rather
    # than left to the application.
    add_index :departments, :name, unique: true
  end
end
