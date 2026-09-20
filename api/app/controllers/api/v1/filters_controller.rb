module Api
  module V1
    class FiltersController < ApplicationController
      # What the directory's filter panel is built from. One request rather than
      # three, because the panel cannot be drawn until it has all of them.
      def show
        facets = DirectoryFacetsQuery.new.call

        render json: {
          data: {
            countries: facets.countries,
            departments: facets.departments,
            job_levels: facets.job_levels
          }
        }
      end
    end
  end
end
