class PricesController < ApplicationController
  # GET /prices/:symbol?currency=usd
  def show
    symbol = params[:symbol].to_s.downcase
    currency = params[:currency].to_s.downcase.presence || PriceStore::DEFAULT_CURRENCY

    unless SymbolValidator.valid?(symbol) && CurrencyValidator.valid?(currency)
      return render json: { error: "invalid symbol or currency format" }, status: :unprocessable_entity
    end

    payload = PriceStore.read(symbol, currency: currency)

    if payload
      render json: payload
    else
      render json: { error: "no price cached yet for #{symbol} #{currency}" }, status: :not_found
    end
  end
end
