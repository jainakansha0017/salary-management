# The React app is served from a different origin, so the browser will not let
# it call this API unless the API says so.
#
# Origins come from the environment rather than being hardcoded, because the
# deployed UI's hostname is not known until it is deployed. There is deliberately
# no "*" fallback: a wildcard is harmless while the API is anonymous and quietly
# becomes a vulnerability the day authentication is added, and it is easier to
# get right now than to remember to tighten later.
allowed_origins = ENV.fetch("CORS_ORIGINS", "http://localhost:5173")
                     .split(",")
                     .map(&:strip)
                     .reject(&:empty?)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)

    resource "/api/*", headers: :any, methods: %i[get post patch put delete options head]
  end
end
