Rails.application.routes.draw do
  # Versioned from the first endpoint. The React app is deployed separately and
  # will not always be redeployed in step with the API, so the URL has to say
  # which contract the client is holding.
  # JSON unless the URL says otherwise. Without this, a request that sends no
  # `Accept` header — curl, a health check, most HTTP clients out of the box —
  # is read as asking for HTML, and is answered with 406 by any endpoint that
  # offers more than one format. An explicit `.csv` still overrides it.
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :employees, only: [ :index, :show ] do
        # Nested and create-only: a pay change belongs to one person, and the
        # history is append-only, so there is nothing to update or delete.
        resources :salary_changes, only: [ :create ]
      end

      # Singular: there is one set of filter options, not a collection of them.
      # Department ids are assigned by the database, so the client has to be
      # told what they are rather than holding a constant that is right on one
      # machine and wrong everywhere else.
      resource :filters, only: [ :show ]

      # Not a REST resource — these are questions, not things. Named after what
      # they answer rather than forced into a `resources` block.
      get "analytics/summary", to: "analytics#summary"
      get "analytics/breakdown", to: "analytics#breakdown"
    end
  end

  # Returns 200 if the app boots with no exceptions. The host's health check
  # uses it, so a broken deploy fails rather than serving errors.
  get "up" => "rails/health#show", as: :rails_health_check
end
