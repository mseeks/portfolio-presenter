class AlphaVantage
  attr_accessor :api, :api_key, :macd_query, :symbol

  def initialize(symbol)
    @symbol = symbol
    @api = RestClient::Resource.new("https://www.alphavantage.co")
    @api_key = ENV["ALPHAVANTAGE_API_KEY"]
  end

  def macd_query
    @macd_query ||= JSON.parse(@api["query"].get(
      {
        params: {
          function: "MACD",
          symbol: @symbol,
          interval: "daily",
          series_type: "close",
          apikey: @api_key
        }
      }
    ).body)["Technical Analysis: MACD"].map{|key, entry|
      {
        begins_at: key,
        macd: entry["MACD"].to_f,
        macd_signal: entry["MACD_Signal"].to_f
      }
    }
  end
end
