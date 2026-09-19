require "rails_helper"

RSpec.describe "POST /api/v1/employees/:employee_id/salary_changes" do
  let(:employee) { create(:employee) }
  let(:body) { response.parsed_body }

  # Reference data the endpoint needs to exist, not a subject of any example.
  before { create(:currency) }

  def post_change(**overrides)
    post "/api/v1/employees/#{employee.id}/salary_changes", params: {
      salary_change: {
        amount_minor: 99_000_00,
        currency_code: "USD",
        effective_from: "2026-10-01",
        reason: "merit_increase"
      }.merge(overrides)
    }
  end

  describe "recording a raise" do
    before { create(:compensation, employee: employee, amount_minor: 90_000_00, effective_from: Date.new(2026, 1, 1)) }

    it "returns the new period, so the UI does not have to refetch to show it" do
      post_change

      expect(response).to have_http_status(:created)
      expect(body["data"]).to include(
        "current" => true,
        "reason" => "merit_increase",
        "effective_from" => "2026-10-01"
      )
      expect(body["data"]["amount"]).to include("amount_minor" => 99_000_00, "currency_code" => "USD")
    end

    it "closes the previous period rather than overwriting the old amount" do
      expect { post_change }.to change { employee.compensations.count }.from(1).to(2)

      expect(employee.compensations.order(:effective_from).map(&:amount_minor)).to eq([ 90_000_00, 99_000_00 ])
      expect(employee.compensations.current.count).to eq(1)
    end

    it "carries a note through when one is given" do
      post_change(note: "Off-cycle, agreed at the April review")

      expect(body["data"]["note"]).to eq("Off-cycle, agreed at the April review")
    end
  end

  describe "when the request is rejected" do
    it "returns the failures keyed by field, so the form can mark the right input" do
      post_change(amount_minor: "99000.50", reason: "felt_like_it")

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["error"]["code"]).to eq("validation_failed")
      expect(body["error"]["details"].keys).to contain_exactly("amount_minor", "reason")
    end

    it "records nothing at all when any part of the request is bad" do
      expect { post_change(amount_minor: -1) }.not_to change(Compensation, :count)
    end

    # Two clicks on a submit button is the ordinary way this happens.
    it "refuses a second identical change rather than recording the same raise twice" do
      post_change
      expect(response).to have_http_status(:created)

      expect { post_change }.not_to change(Compensation, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body["error"]["details"]["effective_from"].first).to include("must take effect after")
    end

    # The race itself is covered against a real database in
    # spec/integration/concurrent_salary_changes_spec.rb. This checks only that
    # losing it is reported as a conflict rather than as bad input.
    it "answers 409 when another change landed first" do
      allow(RecordSalaryChange).to receive(:call)
        .and_raise(RecordSalaryChange::ConcurrentChange, "reload and try again")

      post_change

      expect(response).to have_http_status(:conflict)
      expect(body["error"]).to include("code" => "conflict", "message" => "reload and try again")
    end

    it "answers with JSON when the employee does not exist" do
      post "/api/v1/employees/0/salary_changes", params: { salary_change: { amount_minor: 1 } }

      expect(response).to have_http_status(:not_found)
      expect(body["error"]["code"]).to eq("not_found")
    end

    it "names the key it wanted when the body is nested wrongly" do
      post "/api/v1/employees/#{employee.id}/salary_changes", params: { amount_minor: 99_000_00 }

      expect(response).to have_http_status(:bad_request)
      expect(body["error"]).to include("code" => "parameter_missing")
      expect(body["error"]["message"]).to include("salary_change")
    end
  end
end
