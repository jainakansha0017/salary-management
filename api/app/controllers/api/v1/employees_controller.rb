module Api
  module V1
    class EmployeesController < ApplicationController
      def index
        query = EmployeeDirectoryQuery.new(directory_params)

        respond_to do |format|
          format.json { render json: json_page(query) }
          # Same URL, same parameters, no page boundary. An export is the list
          # the user is already looking at, so there is no second set of
          # filters to keep in step and nothing to explain about why a download
          # holds different people from the screen it came from.
          format.csv { send_csv(query) }
        end
      end

      def show
        # `effective_compensation` is one of `compensations`, but Rails will not
        # infer that, so it is preloaded too. Both are a fixed number of
        # queries for one employee, which is the property that matters.
        employee = Employee.preload(
          :department,
          effective_compensation: [ :currency, :base_currency ],
          compensations: [ :currency, :base_currency ]
        ).find(params[:id])

        render json: { data: EmployeeDetailSerializer.new(employee).as_json }
      end

      private

      # Unrecognised parameters are dropped rather than rejected. Every value
      # here is a view preference, and the query object already falls back to a
      # sensible default for anything it does not understand, so there is
      # nothing a bad value can do except be ignored.
      def directory_params
        params.permit(
          :q, :status, :sort, :direction, :page, :page_size,
          country_code: [], department_id: [], job_level: []
        )
      end

      def json_page(query)
        page = query.call

        {
          data: page.records.map { |employee| EmployeeSummarySerializer.new(employee).as_json },
          meta: meta_for(page).merge(applied: query.applied)
        }
      end

      def meta_for(page)
        {
          page: page.page,
          page_size: page.page_size,
          total_count: page.total_count,
          total_pages: page.total_pages
        }
      end

      # Dated in the filename because an export is a snapshot, and two of them
      # in a downloads folder are otherwise indistinguishable.
      def send_csv(query)
        send_data EmployeeCsvSerializer.new(query.all).call,
                  type: "text/csv",
                  filename: "employees-#{Date.current.iso8601}.csv",
                  disposition: "attachment"
      end
    end
  end
end
