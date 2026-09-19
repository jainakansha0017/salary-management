class Employee < ApplicationRecord
  belongs_to :department

  has_many :compensations, dependent: :destroy

  # A distinct association rather than `compensations.current.first`, so the
  # directory can eager-load current pay for a page of employees in one query
  # instead of one per employee.
  has_one :current_compensation, -> { current },
          class_name: "Compensation", inverse_of: :employee, dependent: nil

  # Stored values are canonical, so lookups and uniqueness checks do not have to
  # care how the data was typed in.
  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :country_code, with: ->(code) { code.strip.upcase }

  validates :employee_number, presence: true, uniqueness: true
  validates :first_name, :last_name, :job_title, :job_level, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :country_code, format: { with: /\A[A-Z]{2}\z/, message: "must be an ISO 3166-1 alpha-2 code" }
  validates :hired_on, presence: true
  validate :ended_on_cannot_precede_hired_on

  # One expression covering everything HR types into the search box. It is
  # indexed verbatim by the trigram index added in
  # 20260919110000_add_search_index_to_employees, so changing it without a
  # matching migration would quietly turn search back into a sequential scan.
  SEARCHABLE_TEXT = "(employees.first_name || ' ' || employees.last_name || " \
                    "' ' || employees.email || ' ' || employees.employee_number)".freeze

  # Substring rather than prefix matching: "kowal" should find Kowalski, and a
  # surname is not always the first thing someone types.
  scope :search, ->(term) {
    cleaned = term.to_s.strip
    next all if cleaned.empty?

    where("#{SEARCHABLE_TEXT} ILIKE ?", "%#{sanitize_sql_like(cleaned)}%")
  }

  # Expressed as "active on a date" rather than a bare `active`, because every
  # analytics figure is really a question about a point in time. `active` is the
  # common case of that, not a separate idea.
  scope :active_on, ->(date) {
    where(hired_on: ..date).where("employees.ended_on IS NULL OR employees.ended_on >= ?", date)
  }
  scope :active, -> { active_on(Date.current) }

  def full_name
    "#{first_name} #{last_name}"
  end

  def active_on?(date)
    hired_on <= date && (ended_on.nil? || ended_on >= date)
  end

  private

  def ended_on_cannot_precede_hired_on
    return if ended_on.blank? || hired_on.blank?
    return if ended_on >= hired_on

    errors.add(:ended_on, "cannot be before the hire date")
  end
end
