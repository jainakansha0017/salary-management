module Api
  module V1
    class AnalyticsController < ApplicationController
      def summary
        query = PayrollSummaryQuery.new(analytics_params)

        render json: {
          data: PayrollSummarySerializer.new(query.call).as_json,
          meta: { applied: query.applied }
        }
      end

      def breakdown
        query = PayrollBreakdownQuery.new(analytics_params)

        render json: {
          data: PayrollBreakdownSerializer.new(query.call).as_json,
          meta: { applied: query.applied }
        }
      end

      private

      # The same filters the directory takes, so a chart and a list can be shown
      # for one set of parameters, plus the date the question is asked about.
      def analytics_params
        params.permit(:q, :as_of, :dimension, country_code: [], department_id: [], job_level: [])
      end
    end
  end
end
