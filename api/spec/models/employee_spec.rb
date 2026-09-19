require "rails_helper"

RSpec.describe Employee do
  describe "normalisation" do
    it "stores email in lowercase so lookups do not depend on how it was typed" do
      employee = create(:employee, email: "  Ada.Lovelace@ACME.example ")

      expect(employee.email).to eq("ada.lovelace@acme.example")
    end

    it "stores the country code in uppercase" do
      employee = create(:employee, country_code: "gb")

      expect(employee.country_code).to eq("GB")
    end
  end

  describe "validations" do
    it "rejects a country code that is not ISO 3166-1 alpha-2" do
      employee = build(:employee, country_code: "GBR")

      expect(employee).not_to be_valid
      expect(employee.errors[:country_code]).to include("must be an ISO 3166-1 alpha-2 code")
    end

    it "rejects an end date before the hire date" do
      employee = build(:employee, hired_on: Date.new(2020, 1, 1), ended_on: Date.new(2019, 12, 31))

      expect(employee).not_to be_valid
      expect(employee.errors[:ended_on]).to include("cannot be before the hire date")
    end

    it "allows an employee who left on their hire date" do
      employee = build(:employee, hired_on: Date.new(2020, 1, 1), ended_on: Date.new(2020, 1, 1))

      expect(employee).to be_valid
    end

    it "requires the employee number to be unique" do
      create(:employee, employee_number: "ACME-00001")
      duplicate = build(:employee, employee_number: "ACME-00001")

      expect(duplicate).not_to be_valid
    end
  end

  describe ".active_on" do
    # Frozen so the expectations describe the domain rule rather than today's date.
    let(:review_date) { Date.new(2026, 6, 30) }

    it "includes an employee hired before the date who has not left" do
      employee = create(:employee, hired_on: Date.new(2020, 1, 1), ended_on: nil)

      expect(described_class.active_on(review_date)).to include(employee)
    end

    it "excludes an employee who had not yet been hired on that date" do
      employee = create(:employee, hired_on: Date.new(2026, 7, 1))

      expect(described_class.active_on(review_date)).not_to include(employee)
    end

    it "excludes an employee who had already left" do
      employee = create(:employee, hired_on: Date.new(2020, 1, 1), ended_on: Date.new(2026, 6, 29))

      expect(described_class.active_on(review_date)).not_to include(employee)
    end

    it "includes an employee whose last day is the date itself" do
      employee = create(:employee, hired_on: Date.new(2020, 1, 1), ended_on: review_date)

      expect(described_class.active_on(review_date)).to include(employee)
    end
  end

  describe ".active" do
    it "reports employees who are active as of today" do
      current = create(:employee)
      departed = create(:employee, :departed)

      expect(described_class.active).to include(current)
      expect(described_class.active).not_to include(departed)
    end
  end

  describe ".search" do
    let!(:kowalski) { create(:employee, first_name: "Anna", last_name: "Kowalski", email: "anna.kowalski@acme.example") }
    let!(:tanaka) { create(:employee, first_name: "Yui", last_name: "Tanaka", email: "yui.tanaka@acme.example", employee_number: "ACME-09112") }

    it "matches a fragment from the middle of a surname" do
      expect(described_class.search("owal")).to contain_exactly(kowalski)
    end

    it "ignores case, because nobody types a surname the way it is stored" do
      expect(described_class.search("KOWALSKI")).to contain_exactly(kowalski)
    end

    it "matches on email and on employee number, so one box covers all of them" do
      expect(described_class.search("yui.tanaka@")).to contain_exactly(tanaka)
      expect(described_class.search("09112")).to contain_exactly(tanaka)
    end

    it "matches across the first and last name together" do
      expect(described_class.search("Anna Kowalski")).to contain_exactly(kowalski)
    end

    it "returns everything for a blank term rather than nothing" do
      expect(described_class.search("  ")).to include(kowalski, tanaka)
    end

    it "treats a wildcard as a literal character, not as a pattern" do
      # Without escaping, "%" would match every employee in the company.
      expect(described_class.search("%")).to be_empty
    end

    # The whole point of SEARCHABLE_TEXT is that it matches the expression the
    # trigram index is built on. At test-suite row counts the planner would
    # choose a sequential scan anyway, so seqscan is disabled to ask the
    # narrower question: *can* this query use the index?
    it "is answerable from the trigram index" do
      plan = described_class.connection.execute(<<~SQL.squish).map { |row| row["QUERY PLAN"] }.join("\n")
        SET LOCAL enable_seqscan = off;
        EXPLAIN #{described_class.search('kowal').to_sql}
      SQL

      expect(plan).to include("index_employees_on_searchable_text")
    end
  end

  describe "#full_name" do
    it "joins the first and last name" do
      employee = build(:employee, first_name: "Ada", last_name: "Lovelace")

      expect(employee.full_name).to eq("Ada Lovelace")
    end
  end
end
