require "rails_helper"

RSpec.describe Department do
  it "requires a name" do
    expect(build(:department, name: nil)).not_to be_valid
  end

  it "treats names differing only by case as duplicates, so reporting stays canonical" do
    create(:department, name: "Engineering")

    expect(build(:department, name: "engineering")).not_to be_valid
  end

  it "refuses to be destroyed while employees still belong to it" do
    department = create(:department)
    create(:employee, department: department)

    expect(department.destroy).to be(false)
    expect(department.errors[:base]).to be_present
  end
end
