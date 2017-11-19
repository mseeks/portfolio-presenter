require "active_support/all"
require "json"
require "rest-client"
require "sinatra"
require "sinatra/cross_origin"

require "./lib/alpha_vantage"

set :bind, "0.0.0.0"
set :port, 80

configure do
  enable :cross_origin
end

before do
  @api = RestClient::Resource.new("https://api.robinhood.com")
  @api_headers = {
    accept: "application/json",
    Authorization: "Token #{ENV["ROBINHOOD_TOKEN"]}"
  }
end

get "/portfolio" do
  @account = JSON.parse(@api["accounts/"].get(@api_headers).body)["results"].first
  @portfolio = JSON.parse(RestClient.get(@account["portfolio"], @api_headers).body)

  content_type :json
  {
    portfolio_value: @portfolio["extended_hours_equity"] || @portfolio["equity"]
  }.to_json
end

get "/graph/portfolio/:period" do
  # interval = 5minute | 10minute + span = day, week
  # interval = day + span = year
  # interval = week
  interval, span = case params["period"]
  when "1d"
    ["5minute", "day"]
  when "1w"
    ["10minute", "week"]
  when "1m"
    ["day", nil]
  when "3m"
    ["day", "year"]
  when "1y"
    ["day", "year"]
  when "all"
    ["week", nil]
  end

  formatted_span = if span
    "&span=#{span}"
  else
    ""
  end

  @account = JSON.parse(@api["accounts/"].get(@api_headers).body)["results"].first
  @portfolio = JSON.parse(RestClient.get(@account["portfolio"], @api_headers).body)
  @historicals = JSON.parse(@api["/portfolios/historicals/#{@account["account_number"]}?interval=#{interval}#{formatted_span}"].get(@api_headers).body)

  historicals = case params["period"]
  when "1d"
    @historicals["equity_historicals"]
  when "1w"
    @historicals["equity_historicals"]
  when "1m"
    @historicals["equity_historicals"].last(30)
  when "3m"
    @historicals["equity_historicals"].select do |historical|
      Time.parse(historical["begins_at"]) > Time.now - 3.months
    end
  when "1y"
    @historicals["equity_historicals"]
  when "all"
    @historicals["equity_historicals"]
  end

  current_equity = @portfolio["extended_hours_equity"] || @portfolio["equity"]

  content_type :json
  {
    current_return: current_equity.to_f - historicals.first["adjusted_open_equity"].to_f,
    historicals: historicals
  }.to_json
end

get "/positions" do
  @account = JSON.parse(@api["accounts/"].get(@api_headers).body)["results"].first

  @positions = JSON.parse(RestClient.get(@account["positions"] + "?nonzero=true", @api_headers).body)["results"].map do |position|
    position["instrument"] = JSON.parse(RestClient.get(position["instrument"], @api_headers).body)

    position
  end

  cash = @account["buying_power"].to_f

  content_type :json
  {
    positions: @positions.map{|position|
      current_quote_response = JSON.parse(RestClient.get(position["instrument"]["quote"]).body)
      current_quote = current_quote_response["last_extended_hours_trade_price"] || current_quote_response["last_trade_price"]
      current_quote = current_quote.to_f
      quantity = position["quantity"].to_f
      average_buy_price = position["average_buy_price"].to_f
      holding_value = current_quote * quantity
      cost_basis = average_buy_price * quantity
      holding_change = holding_value - cost_basis

      {
        average_buy_price: average_buy_price,
        cost_basis: cost_basis,
        holding_change: holding_change,
        holding_value: holding_value,
        name: position["instrument"]["simple_name"],
        quantity: quantity,
        symbol: position["instrument"]["symbol"]
      }
    }.push({
      average_buy_price: cash,
      cost_basis: cash,
      holding_change: 0,
      holding_value: cash,
      name: "Buying Power",
      quantity: 1.0,
      symbol: "CASH"
    }).sort_by{|position| position[:holding_value] }.reverse
  }.to_json
end

get "/positions/:symbol/signals/:period" do
  # interval = 5minute | 10minute + span = day, week
  # interval = day + span = year
  # interval = week
  interval, span = case params[:period]
  when "1d"
    ["5minute", "day"]
  when "1w"
    ["10minute", "week"]
  when "1m"
    ["day", nil]
  when "3m"
    ["day", "year"]
  when "1y"
    ["day", "year"]
  when "all"
    ["week", nil]
  end

  formatted_span = if span
    "&span=#{span}"
  else
    ""
  end

  @account = JSON.parse(@api["accounts/"].get(@api_headers).body)["results"].first
  @portfolio = JSON.parse(RestClient.get(@account["portfolio"], @api_headers).body)
  historicals = JSON.parse(@api["/portfolios/historicals/#{@account["account_number"]}?interval=#{interval}#{formatted_span}"].get(@api_headers).body)

  historicals = case params[:period]
  when "1d"
    historicals["equity_historicals"]
  when "1w"
    historicals["equity_historicals"]
  when "1m"
    historicals["equity_historicals"].last(30)
  when "3m"
    historicals["equity_historicals"].select do |historical|
      Time.parse(historical["begins_at"]) > Time.now - 3.months
    end
  when "1y"
    historicals["equity_historicals"]
  when "all"
    historicals["equity_historicals"]
  end

  historicals = historicals.map{|historical| historical["begins_at"] }

  signals = AlphaVantage.new(params[:symbol].upcase).macd_query
  signals = signals.select{|signal|
    first_historical_time = Time.parse(historicals.first)
    last_historical_time = Time.parse(historicals.last)
    signal_time = Time.parse(signal[:begins_at])

    signal_time >= first_historical_time && signal_time <= last_historical_time
  }

  content_type :json

  {
    signals: signals
  }.to_json
end
