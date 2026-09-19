class ApplicationController < ActionController::API
  # A JSON client that asks for an employee who does not exist should get JSON
  # back. Left alone, Rails answers with an HTML error page, which the UI would
  # have to parse before it could tell the user anything useful.
  rescue_from ActiveRecord::RecordNotFound do |error|
    render_error(
      code: "not_found",
      message: "#{error.model || 'Record'} not found",
      status: :not_found
    )
  end

  # Rails answers a missing top-level parameter with an HTML 400 for the same
  # reason, and a client that sent the body under the wrong key deserves to be
  # told which key it was.
  rescue_from ActionController::ParameterMissing do |error|
    render_error(
      code: "parameter_missing",
      message: "Missing required parameter: #{error.param}",
      status: :bad_request
    )
  end

  private

  # One error shape for the whole API: a stable `code` for the client to branch
  # on, a `message` fit to show a person, and `details` keyed by field when the
  # problem belongs to a particular input.
  def render_error(code:, message:, status:, details: nil)
    payload = { code: code, message: message }
    payload[:details] = details if details.present?

    render json: { error: payload }, status: status
  end
end
