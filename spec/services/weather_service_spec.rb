require 'rails_helper'

RSpec.describe WeatherService, type: :service do
  let(:service) { described_class.new }
  let(:valid_address) { "1600 Pennsylvania Ave NW, Washington, DC" }
  let(:invalid_address) { "Invalid Address 99999" }

  # Sample response data for mocking
  let(:geocoding_response) do
    {
      "result" => {
        "addressMatches" => [
          {
            "matchedAddress" => "1600 PENNSYLVANIA AVE NW, WASHINGTON, DC, 20500",
            "coordinates" => {
              "x" => -77.0365,
              "y" => 38.8977
            }
          }
        ]
      }
    }
  end

  let(:grid_response) do
    {
      "properties" => {
        "gridId" => "LWX",
        "gridX" => 97,
        "gridY" => 71,
        "forecast" => "https://api.weather.gov/gridpoints/LWX/97,71/forecast",
        "forecastHourly" => "https://api.weather.gov/gridpoints/LWX/97,71/forecast/hourly"
      }
    }
  end

  let(:current_weather_response) do
    {
      "properties" => {
        "periods" => [
          {
            "number" => 1,
            "name" => "This Hour",
            "startTime" => "2024-01-15T14:00:00-05:00",
            "endTime" => "2024-01-15T15:00:00-05:00",
            "isDaytime" => true,
            "temperature" => 72,
            "temperatureUnit" => "F",
            "windSpeed" => "10 mph",
            "windDirection" => "SW",
            "shortForecast" => "Partly Cloudy",
            "detailedForecast" => "Partly cloudy skies with humidity around 65%"
          }
        ]
      }
    }
  end

  let(:forecast_response) do
    {
      "properties" => {
        "periods" => [
          {
            "number" => 1,
            "name" => "Today",
            "startTime" => "2024-01-15T06:00:00-05:00",
            "endTime" => "2024-01-15T18:00:00-05:00",
            "isDaytime" => true,
            "temperature" => 78,
            "temperatureUnit" => "F",
            "shortForecast" => "Sunny",
            "detailedForecast" => "Sunny skies throughout the day"
          },
          {
            "number" => 2,
            "name" => "Tonight",
            "startTime" => "2024-01-15T18:00:00-05:00",
            "endTime" => "2024-01-16T06:00:00-05:00",
            "isDaytime" => false,
            "temperature" => 62,
            "temperatureUnit" => "F",
            "shortForecast" => "Clear",
            "detailedForecast" => "Clear skies overnight"
          }
        ]
      }
    }
  end

  before do
    # Mock Redis to avoid dependency on actual Redis instance
    allow(REDIS_CLIENT).to receive(:ping).and_return("PONG")
    allow(REDIS_CLIENT).to receive(:get).and_return(nil)
    allow(REDIS_CLIENT).to receive(:setex).and_return("OK")

    # Mock HTTP.persistent for both URLs to avoid "unexpected arguments" errors
    @geocode_client = instance_double(HTTP::Client)
    @weather_client = instance_double(HTTP::Client)

    allow(HTTP).to receive(:persistent).with("https://geocoding.geo.census.gov").and_return(@geocode_client)
    allow(HTTP).to receive(:persistent).with("https://api.weather.gov").and_return(@weather_client)
    allow(@weather_client).to receive(:headers).and_return(@weather_client)
  end

  describe '#get_weather_forecast' do
    context 'with valid address and successful API calls' do
      before do
        # Use the already mocked clients from the main before block
        setup_successful_api_mocks(@geocode_client, @weather_client)
      end

      it 'returns complete weather data with correct structure' do
        result = service.get_weather_forecast(valid_address)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:address)
        expect(result).to have_key(:current)
        expect(result).to have_key(:forecast)
        expect(result).to have_key(:from_cache)
        expect(result[:from_cache]).to be false
      end

      it 'returns properly formatted current weather data' do
        result = service.get_weather_forecast(valid_address)
        current = result[:current]

        expect(current).to include(
          temperature: 72,
          condition: "Partly Cloudy",
          description: "Partly Cloudy",
          wind_speed: 10,
          high: 78,
          low: 62
        )
        expect(current[:humidity]).to be_between(30, 80)
      end

      it 'returns properly formatted forecast array' do
        result = service.get_weather_forecast(valid_address)
        forecast = result[:forecast]

        expect(forecast).to be_an(Array)
        expect(forecast.first).to include(
          date: "Monday, Jan 15",
          high: 78,
          low: 62,
          condition: "Sunny",
          description: "Sunny"
        )
      end

      it 'caches the result in Redis' do
        expect(REDIS_CLIENT).to receive(:setex).with(
          "weather_forecast:20500",
          1800, # 30 minutes
          anything
        )

        service.get_weather_forecast(valid_address)
      end
    end

    context 'with cached data available' do
      let(:cached_data) do
        {
          address: "1600 PENNSYLVANIA AVE NW, WASHINGTON, DC, 20500",
          current: { temperature: 75, condition: "Sunny" },
          forecast: [ { date: "Today", high: 80, low: 65 } ]
        }
      end

      before do
        # Mock geocoding to get the cache key (still needed for cache lookup)
        geocode_response_mock = instance_double(HTTP::Response)
        allow(@geocode_client).to receive(:get).and_return(geocode_response_mock)
        allow(geocode_response_mock).to receive_message_chain(:status, :success?).and_return(true)
        allow(geocode_response_mock).to receive(:parse).and_return(geocoding_response)

        # Mock cache hit
        allow(REDIS_CLIENT).to receive(:get).with("weather_forecast:20500").and_return(cached_data.to_json)
      end

      it 'returns cached data with from_cache flag set to true' do
        result = service.get_weather_forecast(valid_address)

        expect(result[:from_cache]).to be true
        expect(result[:current][:temperature]).to eq(75)
      end

      it 'does not make API calls when cache hit occurs' do
        # Should only call geocoding API to get cache key, not weather APIs
        expect(@weather_client).not_to receive(:get)

        service.get_weather_forecast(valid_address)
      end
    end

    context 'with invalid address' do
      before do
        # Use the already mocked client and set it up for invalid address response
        geocode_response_mock = instance_double(HTTP::Response)
        allow(@geocode_client).to receive(:get).and_return(geocode_response_mock)
        allow(geocode_response_mock).to receive_message_chain(:status, :success?).and_return(true)
        allow(geocode_response_mock).to receive(:parse).and_return({ "result" => { "addressMatches" => [] } })
      end

      it 'returns error message for invalid address' do
        result = service.get_weather_forecast(invalid_address)

        expect(result).to eq({ error: "Address not found" })
      end
    end

    context 'when API calls fail' do
      before do
        # Use the already mocked client and set it up for API failure
        geocode_response_mock = instance_double(HTTP::Response)
        allow(@geocode_client).to receive(:get).and_return(geocode_response_mock)
        allow(geocode_response_mock).to receive_message_chain(:status, :success?).and_return(false)
      end

      it 'handles geocoding API failures gracefully' do
        result = service.get_weather_forecast(valid_address)

        expect(result).to eq({ error: "Address not found" })
      end
    end

    context 'when Redis is unavailable' do
      before do
        allow(REDIS_CLIENT).to receive(:ping).and_raise(Redis::BaseError)
        # Setup successful API mocks for this test
        setup_successful_api_mocks(@geocode_client, @weather_client)
      end

      it 'continues to work without caching' do
        result = service.get_weather_forecast(valid_address)

        expect(result).to have_key(:address)
        expect(result).to have_key(:current)
        expect(result).to have_key(:forecast)
        expect(result[:from_cache]).to be false
      end
    end
  end

  describe 'private methods' do
    describe '#extract_zip_code' do
      it 'extracts 5-digit zip codes' do
        address = "123 Main St, Anytown, ST 12345"
        zip = service.send(:extract_zip_code, address)
        expect(zip).to eq("12345")
      end

      it 'extracts ZIP+4 codes' do
        address = "123 Main St, Anytown, ST 12345-6789"
        zip = service.send(:extract_zip_code, address)
        expect(zip).to eq("12345-6789")
      end

      it 'normalizes address when no zip code found' do
        address = "Some International Address"
        zip = service.send(:extract_zip_code, address)
        expect(zip).to eq("some_international_address")
      end
    end

    describe '#extract_condition' do
      it 'maps sunny conditions correctly' do
        condition = service.send(:extract_condition, "Sunny and clear")
        expect(condition).to eq("Sunny")
      end

      it 'maps rainy conditions correctly' do
        condition = service.send(:extract_condition, "Light rain showers")
        expect(condition).to eq("Rainy")
      end

      it 'handles unknown conditions' do
        condition = service.send(:extract_condition, "Mysterious weather")
        expect(condition).to eq("Mysterious")
      end
    end

    describe '#extract_wind_speed' do
      it 'extracts numeric wind speed' do
        wind_speed = service.send(:extract_wind_speed, "15 mph")
        expect(wind_speed).to eq(15)
      end

      it 'handles range wind speeds' do
        wind_speed = service.send(:extract_wind_speed, "10 to 20 mph")
        expect(wind_speed).to eq(10)
      end

      it 'returns 0 for invalid wind speed' do
        wind_speed = service.send(:extract_wind_speed, "Variable")
        expect(wind_speed).to eq(0)
      end
    end
  end

  private

  def setup_successful_api_mocks(geocode_client, weather_client)
    # Geocoding mock
    geocode_response_mock = instance_double(HTTP::Response)
    allow(geocode_client).to receive(:get).and_return(geocode_response_mock)
    allow(geocode_response_mock).to receive_message_chain(:status, :success?).and_return(true)
    allow(geocode_response_mock).to receive(:parse).and_return(geocoding_response)

    # Grid info mock
    grid_response_mock = instance_double(HTTP::Response)
    allow(weather_client).to receive(:get).with("/points/38.8977,-77.0365").and_return(grid_response_mock)
    allow(grid_response_mock).to receive_message_chain(:status, :success?).and_return(true)
    allow(grid_response_mock).to receive_message_chain(:body, :to_s).and_return(grid_response.to_json)

    # Current weather mock
    current_response_mock = instance_double(HTTP::Response)
    allow(weather_client).to receive(:get).with("/gridpoints/LWX/97,71/forecast/hourly").and_return(current_response_mock)
    allow(current_response_mock).to receive_message_chain(:status, :success?).and_return(true)
    allow(current_response_mock).to receive_message_chain(:body, :to_s).and_return(current_weather_response.to_json)

    # Forecast mock
    forecast_response_mock = instance_double(HTTP::Response)
    allow(weather_client).to receive(:get).with("/gridpoints/LWX/97,71/forecast").and_return(forecast_response_mock)
    allow(forecast_response_mock).to receive_message_chain(:status, :success?).and_return(true)
    allow(forecast_response_mock).to receive_message_chain(:body, :to_s).and_return(forecast_response.to_json)
  end
end
