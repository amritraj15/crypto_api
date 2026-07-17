Rails.application.routes.draw do
  get "/prices/:symbol", to: "prices#show"
end
