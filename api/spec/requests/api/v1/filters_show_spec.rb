require "rails_helper"

RSpec.describe "GET /api/v1/filters" do
  subject(:facets) { response.parsed_body.fetch("data") }

  def get_filters
    get "/api/v1/filters"
  end

  it "offers the countries people are actually in, without repeating one per employee" do
    create_list(:employee, 3, country_code: "PL")
    create(:employee, country_code: "IN")

    get_filters

    expect(facets.fetch("countries")).to eq(%w[IN PL])
  end

  # The whole reason this endpoint exists: these ids are assigned by the
  # database, so a client that hard-coded them would filter by a department that
  # means something different on another machine.
  it "names departments alongside the ids the filter has to send" do
    engineering = create(:department, name: "Engineering")
    design = create(:department, name: "Design")

    get_filters

    expect(facets.fetch("departments")).to eq(
      [
        { "id" => design.id, "name" => "Design" },
        { "id" => engineering.id, "name" => "Engineering" }
      ]
    )
  end

  # An empty department is a legitimate thing to filter for, and being told
  # nobody is in it is the answer rather than a missing option.
  it "keeps a department with nobody in it" do
    create(:department, name: "Legal")

    get_filters

    expect(facets.fetch("departments").map { |d| d.fetch("name") }).to include("Legal")
  end

  it "offers job levels in order" do
    create(:employee, job_level: "L5")
    create(:employee, job_level: "L2")

    get_filters

    expect(facets.fetch("job_levels")).to eq(%w[L2 L5])
  end

  it "answers with empty lists rather than failing when there is nobody yet" do
    get_filters

    expect(response).to have_http_status(:ok)
    expect(facets).to eq("countries" => [], "departments" => [], "job_levels" => [])
  end
end
