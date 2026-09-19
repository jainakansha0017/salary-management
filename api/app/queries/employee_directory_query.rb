# Turns a set of query-string parameters into one page of the employee
# directory.
#
# It lives outside the controller because the rules here — which columns may be
# sorted on, how a page is bounded, what "active" means — are decisions about
# the domain, and they are far easier to test as an object than through HTTP.
class EmployeeDirectoryQuery
  DEFAULT_PAGE_SIZE = 25
  MAX_PAGE_SIZE = 100

  # An allow-list, not a convenience. The sort key arrives from the internet and
  # `order` will interpolate whatever it is handed.
  SORTS = {
    "name" => [ "employees.last_name", "employees.first_name" ],
    "hired_on" => [ "employees.hired_on" ],
    "employee_number" => [ "employees.employee_number" ],
    "salary" => [ "compensations.amount_base_minor" ]
  }.freeze
  DEFAULT_SORT = "name".freeze

  DIRECTIONS = { "asc" => "ASC", "desc" => "DESC" }.freeze
  DEFAULT_DIRECTIONS = { "salary" => "desc", "hired_on" => "desc" }.freeze

  STATUSES = %w[active departed all].freeze
  DEFAULT_STATUS = "active".freeze

  Page = Struct.new(:records, :total_count, :page, :page_size, keyword_init: true) do
    def total_pages
      return 1 if total_count.zero?

      (total_count.to_f / page_size).ceil
    end
  end

  def initialize(params = {}, scope: Employee.all)
    @params = params.to_h.symbolize_keys
    @scope = scope
  end

  def call
    filtered = apply_filters(scope)

    Page.new(
      records: page_of(filtered),
      total_count: filtered.count,
      page: page_number,
      page_size: page_size
    )
  end

  # The same people in the same order as `call`, without the page boundary —
  # what the CSV export writes.
  #
  # Public so that the export cannot drift from the list it was taken from:
  # identical filters, status rule and ordering by construction, rather than by
  # two objects agreeing to stay in step. What the caller does about loading is
  # its own business; this returns a relation, not records.
  def all
    ordered(apply_filters(scope))
  end

  # Exposed so the API can echo back what it actually did, rather than the
  # client having to guess how its parameters were interpreted.
  def applied
    filter.applied.merge(status: status, sort: sort, direction: direction)
  end

  private

  attr_reader :params, :scope

  # The directory is always a view of now, and "now" has to mean one thing here:
  # a page that filtered by one date and priced by another would be quietly
  # inconsistent with itself.
  def today
    Date.current
  end

  def filter
    @filter ||= EmployeeFilter.new(params)
  end

  def apply_filters(relation)
    by_status(filter.apply(relation))
  end

  def by_status(relation)
    case status
    when "active" then relation.active_on(today)
    # A beginless range compiles to `ended_on < today`, which already excludes
    # the NULLs that mean "still here".
    when "departed" then relation.where(ended_on: ...today)
    else relation
    end
  end

  def page_of(relation)
    ordered(relation)
      .offset((page_number - 1) * page_size)
      .limit(page_size)
      # The directory shows current pay, so it is always loaded — separately
      # rather than through the join, so that a page costs a fixed number of
      # queries no matter how many rows it holds.
      .preload(:department, effective_compensation: [ :currency, :base_currency ])
  end

  def ordered(relation)
    # NULLS LAST keeps people with no current salary — leavers — at the end
    # instead of at the top of a descending sort.
    clauses = SORTS.fetch(sort).map { |column| "#{column} #{DIRECTIONS.fetch(direction)} NULLS LAST" }

    # Without a unique tie-breaker, rows tied on the sort column can appear on
    # two pages or on none, because the database is free to order them
    # differently for each OFFSET.
    clauses << "employees.id ASC"

    relation = relation.left_joins(:effective_compensation) if sort == "salary"
    relation.order(Arel.sql(clauses.join(", ")))
  end

  def status
    @status ||= STATUSES.include?(params[:status]) ? params[:status] : DEFAULT_STATUS
  end

  def sort
    @sort ||= SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT
  end

  def direction
    @direction ||= DIRECTIONS.key?(params[:direction]) ? params[:direction] : DEFAULT_DIRECTIONS.fetch(sort, "asc")
  end

  def page_number
    @page_number ||= [ Integer(params[:page], exception: false) || 1, 1 ].max
  end

  # Capped rather than rejected: an unbounded page size is a way to ask the
  # server to load 10,000 rows into memory, and CSV export is the supported way
  # to get everything.
  def page_size
    @page_size ||= (Integer(params[:page_size], exception: false) || DEFAULT_PAGE_SIZE).clamp(1, MAX_PAGE_SIZE)
  end
end
