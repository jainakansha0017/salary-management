module Api
  module V1
    # Pay changes are recorded, never edited. There is no update and no destroy
    # here by design: correcting a mistake is itself a change, with a
    # `correction` reason and a date, so the record of what was believed at the
    # time survives (ADR-2).
    class SalaryChangesController < ApplicationController
      def create
        form = SalaryChangeForm.new(employee: employee, **salary_change_params)

        if form.save
          render json: { data: CompensationSerializer.new(form.compensation).as_json }, status: :created
        else
          render_error(
            code: "validation_failed",
            message: "The salary change was not recorded",
            details: form.errors.to_hash,
            status: :unprocessable_content
          )
        end
      end

      private

      def employee
        @employee ||= Employee.find(params[:employee_id])
      end

      def salary_change_params
        params
          .require(:salary_change)
          .permit(:amount_minor, :currency_code, :effective_from, :reason, :note)
          .to_h
          .symbolize_keys
      end
    end
  end
end
