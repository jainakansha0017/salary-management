class Department < ApplicationRecord
  has_many :employees, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  scope :by_name, -> { order(:name) }
end
