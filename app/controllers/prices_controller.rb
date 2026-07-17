class PricesController < ApplicationController
  # GET /prices/:symbol
  def show
    symbol = params[:symbol].to_s.downcase

    unless SymbolValidator.valid?(symbol)
      return render json: { error: "invalid symbol format" }, status: :unprocessable_entity
    end

    payload = PriceStore.read(symbol)

    if payload
      render json: payload
    else
      render json: { error: "no price cached yet for #{symbol}" }, status: :not_found
    end
  end
end
