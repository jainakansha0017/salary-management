class ApplicationController < ActionController::API
  # A JSON client that asks for an employee who does not exist should get JSON
  # back. Left alone, Rails answers with an HTML error page, which the UI would
  # have to parse before it could tell the user anything useful.
  rescue_from ActiveRecord::RecordNotFound do |error|
    render json: {
      error: { code: "not_found", message: "#{error.model || 'Record'} not found" }
    }, status: :not_found
  end
end
