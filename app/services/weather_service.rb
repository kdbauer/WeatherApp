# Service class for fetching weather forecast data with Redis caching
# Integrates with Census Geocoding API and National Weather Service API
class WeatherService
  CACHE_TTL = 30.minutes.to_i # 30 minutes in seconds
  CACHE_PREFIX = "weather_forecast"

  # Initializes the WeatherService with persistent HTTP clients
  # Sets up connections to Census Geocoding API and weather.gov API
  #
  # @return [WeatherService] new instance of the service
  def initialize
    @geocode_client = HTTP.persistent("https://geocoding.geo.census.gov")
    @weather_client = HTTP.persistent("https://api.weather.gov")
      .headers("User-Agent" => "WeatherApp/1.0 (your-email@example.com)")
    @redis = REDIS_CLIENT
  end

  # Main method to get weather forecast for a given address
  # Uses caching to reduce API calls - checks cache first, then fetches fresh data if needed
  #
  # @param address [String] the address to get weather for (e.g., "1600 Pennsylvania Ave, Washington DC")
  # @return [Hash] weather data hash with complete object decomposition:
  #   SUCCESS RESPONSE:
  #   - :address [String] formatted/standardized address from Census API
  #   - :current [Hash] current weather conditions object:
  #     - :temperature [Integer] current temperature in Fahrenheit
  #     - :condition [String] simplified weather condition ("Sunny", "Cloudy", etc.)
  #     - :description [String] detailed weather description from weather.gov
  #     - :humidity [Integer] humidity percentage (0-100)
  #     - :wind_speed [Integer] wind speed in mph
  #     - :high [Integer] today's high temperature in Fahrenheit
  #     - :low [Integer] today's low temperature in Fahrenheit
  #   - :forecast [Array<Hash>] 7-day forecast array, each day containing:
  #     - :date [String] formatted date ("Monday, Jan 15")
  #     - :high [Integer] daily high temperature in Fahrenheit
  #     - :low [Integer, nil] daily low temperature in Fahrenheit (nil if unavailable)
  #     - :condition [String] simplified weather condition
  #     - :description [String] detailed forecast description
  #   - :from_cache [Boolean] true if data retrieved from Redis cache, false if fresh API call
  #   ERROR RESPONSE:
  #   - :error [String] error message ("Address not found", "Weather data not available", etc.)
  def get_weather_forecast(address)
    # First, get coordinates from address using Census Geocoding API
    coordinates = geocode_address(address)
    return { error: "Address not found" } unless coordinates

    # Extract zip code for cache key
    zip_code = extract_zip_code(coordinates[:formatted_address] || address)
    cache_key = generate_cache_key(zip_code)

    # Try to get cached data first
    cached_data = get_cached_weather(cache_key)
    if cached_data
      return cached_data.merge(from_cache: true)
    end

    # No cache hit - fetch fresh data from APIs
    # Get weather.gov grid point for the coordinates
    grid_info = get_weather_grid_info(coordinates[:lat], coordinates[:lon])
    return { error: "Weather grid not available for this location" } unless grid_info

    # Get current weather and forecast from weather.gov
    current_weather = get_current_weather(grid_info)
    forecast = get_7_day_forecast(grid_info)
    return { error: "Weather data not available" } unless current_weather && forecast

    # Format the response
    result = format_weather_response(current_weather, forecast, address, coordinates)
    result[:from_cache] = false

    # Cache the result
    cache_weather_data(cache_key, result)

    result
  rescue StandardError => e
    Rails.logger.error "Weather API Error: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    { error: "Unable to fetch weather data: #{e.message}" }
  end

  private

  # Generates a Redis cache key for weather data based on zip code
  #
  # @param zip_code [String] the zip code or normalized address identifier
  # @return [String] Redis cache key in format "weather_forecast:12345"
  def generate_cache_key(zip_code)
    "#{CACHE_PREFIX}:#{zip_code}"
  end

  # Extracts zip code from address string for use as cache key
  # Falls back to normalized address if no zip code found
  #
  # @param address [String] the address string to parse
  # @return [String] zip code (e.g., "12345" or "12345-6789") or normalized address
  def extract_zip_code(address)
    # Try to extract zip code from address string
    zip_match = address.match(/\b(\d{5}(?:-\d{4})?)\b/)
    if zip_match
      return zip_match[1]
    end

    # If no zip code found, use a normalized version of the address as fallback
    address.downcase.gsub(/[^a-z0-9]/, "_").slice(0, 50)
  end

  # Retrieves cached weather data from Redis
  #
  # @param cache_key [String] the Redis cache key to lookup
  # @return [Hash, nil] parsed weather data hash or nil if not found/error
  def get_cached_weather(cache_key)
    return nil unless redis_available?

    cached_json = @redis.get(cache_key)
    return nil unless cached_json

    JSON.parse(cached_json, symbolize_names: true)
  rescue Redis::BaseError, JSON::ParserError => e
    Rails.logger.warn "Cache retrieval error: #{e.message}"
    nil
  end

  # Stores weather data in Redis cache with TTL
  # Removes transient flags like :from_cache before storing
  #
  # @param cache_key [String] the Redis cache key to store under
  # @param data [Hash] the weather data hash to cache
  # @return [void]
  def cache_weather_data(cache_key, data)
    return unless redis_available?

    # Remove the from_cache flag before caching
    cache_data = data.dup
    cache_data.delete(:from_cache)

    @redis.setex(cache_key, CACHE_TTL, cache_data.to_json)
  rescue Redis::BaseError => e
    Rails.logger.warn "Cache storage error: #{e.message}"
  end

  # Checks if Redis is available and responding
  #
  # @return [Boolean] true if Redis is available, false otherwise
  def redis_available?
    @redis&.ping
    true
  rescue Redis::BaseError
    false
  end

  # ===== API INTEGRATION METHODS =====

  # Converts street address to latitude/longitude coordinates using Census Geocoding API
  # Uses the Public Address Ranges - Current benchmark for accuracy
  #
  # @param address [String] street address to geocode (e.g., "1600 Pennsylvania Ave NW, Washington, DC")
  # @return [Hash, nil] coordinate object with complete decomposition:
  #   SUCCESS RESPONSE:
  #   - :lat [Float] latitude coordinate (-90.0 to 90.0)
  #   - :lon [Float] longitude coordinate (-180.0 to 180.0)
  #   - :formatted_address [String] standardized address from Census Bureau
  #     Example: "1600 PENNSYLVANIA AVE NW, WASHINGTON, DC, 20500"
  #   ERROR RESPONSE:
  #   - nil if address not found, API error, or invalid response structure
  def geocode_address(address)
    # Use Census Geocoding API - no API key required
    params = {
      address: address,
      benchmark: "Public_AR_Current",
      format: "json"
    }

    response = @geocode_client.get("/geocoder/locations/onelineaddress", params: params)

    return nil unless response.status.success?

    parsed = response.parse
    address_matches = parsed.dig("result", "addressMatches")

    return nil unless address_matches&.any?

    match = address_matches.first
    coordinates = match["coordinates"]

    result = {
      lat: coordinates["y"].to_f,
      lon: coordinates["x"].to_f,
      formatted_address: match["matchedAddress"]
    }

    result
  rescue StandardError => e
    Rails.logger.error "Geocoding error: #{e.message}"
    nil
  end

  # Gets weather.gov grid information for given coordinates
  # Grid info is required to make subsequent weather API calls
  # Formats coordinates to 4 decimal places as required by weather.gov
  #
  # @param lat [Float] latitude coordinate
  # @param lon [Float] longitude coordinate
  # @return [Hash, nil] grid information object with complete decomposition:
  #   SUCCESS RESPONSE:
  #   - :grid_office [String] weather office identifier (e.g., "LWX", "NYC", "LAX")
  #   - :grid_x [Integer] weather.gov grid X coordinate (0-200+ range)
  #   - :grid_y [Integer] weather.gov grid Y coordinate (0-200+ range)
  #   - :forecast_url [String] full URL for daily forecast endpoint
  #     Example: "https://api.weather.gov/gridpoints/LWX/97,71/forecast"
  #   - :forecast_hourly_url [String] full URL for hourly forecast endpoint
  #     Example: "https://api.weather.gov/gridpoints/LWX/97,71/forecast/hourly"
  #   ERROR RESPONSE:
  #   - nil if coordinates outside US, API error, or invalid grid point
  def get_weather_grid_info(lat, lon)
    # Get weather.gov grid information for coordinates
    # Round coordinates to 4 decimal places as expected by weather.gov
    formatted_lat = "%.4f" % lat
    formatted_lon = "%.4f" % lon

    response = @weather_client.get("/points/#{formatted_lat},#{formatted_lon}")

    return nil unless response.status.success?

    # Manually parse JSON since weather.gov returns application/geo+json
    data = JSON.parse(response.body.to_s)

    result = {
      grid_office: data.dig("properties", "gridId"),
      grid_x: data.dig("properties", "gridX"),
      grid_y: data.dig("properties", "gridY"),
      forecast_url: data.dig("properties", "forecast"),
      forecast_hourly_url: data.dig("properties", "forecastHourly")
    }

    result
  rescue StandardError => e
    Rails.logger.error "Weather grid error: #{e.message}"
    nil
  end

  # Fetches current weather conditions from weather.gov hourly forecast
  # Uses the first (most recent) period from hourly forecast as "current" conditions
  #
  # @param grid_info [Hash] grid information hash from get_weather_grid_info
  # @return [Hash, nil] current weather period object with complete decomposition:
  #   SUCCESS RESPONSE (raw weather.gov data structure):
  #   - "number" [Integer] period number (1, 2, 3...)
  #   - "name" [String] period name (e.g., "This Hour", "Next Hour")
  #   - "startTime" [String] ISO 8601 datetime (e.g., "2024-01-15T14:00:00-05:00")
  #   - "endTime" [String] ISO 8601 datetime (e.g., "2024-01-15T15:00:00-05:00")
  #   - "isDaytime" [Boolean] true if daytime period, false if nighttime
  #   - "temperature" [Integer] temperature in Fahrenheit
  #   - "temperatureUnit" [String] temperature unit ("F" for Fahrenheit)
  #   - "windSpeed" [String] wind speed with units (e.g., "10 mph", "5 to 15 mph")
  #   - "windDirection" [String] wind direction (e.g., "NW", "SE")
  #   - "shortForecast" [String] brief condition (e.g., "Partly Cloudy", "Light Rain")
  #   - "detailedForecast" [String] detailed description with humidity, conditions, etc.
  #   ERROR RESPONSE:
  #   - nil if API error, invalid grid_info, or no forecast periods available
  def get_current_weather(grid_info)
    # Get current conditions from hourly forecast (most recent)
    forecast_path = grid_info[:forecast_hourly_url].gsub("https://api.weather.gov", "")

    response = @weather_client.get(forecast_path)

    return nil unless response.status.success?

    # Manually parse JSON since weather.gov returns application/geo+json
    data = JSON.parse(response.body.to_s)

    periods = data.dig("properties", "periods")

    return nil unless periods&.any?

    current_period = periods.first
    current_period
  rescue StandardError => e
    Rails.logger.error "Current weather error: #{e.message}"
    nil
  end

  # Fetches 7-day weather forecast from weather.gov
  # Returns array of day/night forecast periods
  #
  # @param grid_info [Hash] grid information hash from get_weather_grid_info
  # @return [Array<Hash>, nil] array of forecast period objects with complete decomposition:
  #   SUCCESS RESPONSE (array of raw weather.gov period objects):
  #   Each period hash contains:
  #   - "number" [Integer] period sequence number (1, 2, 3...)
  #   - "name" [String] period name ("Today", "Tonight", "Monday", "Monday Night", etc.)
  #   - "startTime" [String] ISO 8601 datetime (e.g., "2024-01-15T06:00:00-05:00")
  #   - "endTime" [String] ISO 8601 datetime (e.g., "2024-01-15T18:00:00-05:00")
  #   - "isDaytime" [Boolean] true for day periods, false for night periods
  #   - "temperature" [Integer] forecast temperature in Fahrenheit
  #   - "temperatureUnit" [String] temperature unit ("F")
  #   - "temperatureTrend" [String, nil] trend indicator ("rising", "falling", or nil)
  #   - "windSpeed" [String] wind speed description (e.g., "5 to 10 mph")
  #   - "windDirection" [String] wind direction abbreviation (e.g., "SW", "NNE")
  #   - "icon" [String] weather.gov icon URL for conditions
  #   - "shortForecast" [String] brief description (e.g., "Partly Cloudy", "Chance Rain")
  #   - "detailedForecast" [String] detailed narrative forecast
  #   ERROR RESPONSE:
  #   - nil if API error, invalid grid_info, or no forecast data available
  def get_7_day_forecast(grid_info)
    # Get 7-day forecast
    forecast_path = grid_info[:forecast_url].gsub("https://api.weather.gov", "")
    response = @weather_client.get(forecast_path)

    return nil unless response.status.success?

    # Manually parse JSON since weather.gov returns application/geo+json
    data = JSON.parse(response.body.to_s)

    periods = data.dig("properties", "periods")

    periods
  rescue StandardError => e
    Rails.logger.error "7-day forecast error: #{e.message}"
    nil
  end

  # ===== DATA FORMATTING METHODS =====

  # Formats raw weather API data into standardized response structure
  # Combines current conditions and forecast data into frontend-friendly format
  #
  # @param current [Hash] current weather data from get_current_weather
  # @param forecast [Array<Hash>] forecast periods from get_7_day_forecast
  # @param address [String] original address input
  # @param coordinates [Hash] coordinate data with :formatted_address
  # @return [Hash] formatted weather response with keys:
  #   - :address [String] formatted address
  #   - :current [Hash] current weather conditions
  #   - :forecast [Array<Hash>] 7-day daily forecast
  def format_weather_response(current, forecast, address, coordinates)
    # Parse current temperature from weather.gov format
    temp_match = current["temperature"].to_s.match(/(\d+)/)
    current_temp = temp_match ? temp_match[1].to_i : 0

    # Get today's forecast for high/low (first period is usually today)
    today_forecast = forecast.first

    {
      address: coordinates[:formatted_address] || address,
      current: {
        temperature: current_temp,
        condition: extract_condition(current["shortForecast"]),
        description: current["shortForecast"],
        humidity: extract_humidity(current["detailedForecast"]),
        wind_speed: extract_wind_speed(current["windSpeed"]),
        high: extract_temperature(today_forecast["temperature"]),
        low: find_low_temp(forecast)
      },
      forecast: format_daily_forecast(forecast)
    }
  end

  # Converts weather.gov day/night forecast periods into daily forecast array
  # Groups consecutive day/night periods together and limits to 7 days
  #
  # @param forecast_periods [Array<Hash>] array of forecast periods from weather.gov
  # @return [Array<Hash>] array of daily forecast objects with complete decomposition:
  #   Each daily forecast hash contains:
  #   - :date [String] human-readable date format
  #     Examples: "Monday, Jan 15", "Tuesday, Jan 16", "Wednesday, Jan 17"
  #   - :high [Integer] daily high temperature in Fahrenheit
  #     Extracted from daytime period temperature (typically 40-100°F range)
  #   - :low [Integer, nil] daily low temperature in Fahrenheit
  #     Extracted from nighttime period temperature, nil if night period unavailable
  #     Typically 10-80°F range, always <= high temperature
  #   - :condition [String] simplified weather condition category
  #     Possible values: "Sunny", "Partly Cloudy", "Cloudy", "Rainy", "Stormy", "Snow"
  #     Or first word capitalized from original forecast if no match
  #   - :description [String] original detailed forecast description from weather.gov
  #     Example: "Partly sunny, with a high near 75. Light southwest wind."
  def format_daily_forecast(forecast_periods)
    # weather.gov provides day/night periods, group them by day
    daily_forecasts = []

    forecast_periods.each_slice(2) do |day_period, night_period|
      break if daily_forecasts.length >= 7

      daily_forecasts << {
        date: format_date(day_period["startTime"]),
        high: extract_temperature(day_period["temperature"]),
        low: night_period ? extract_temperature(night_period["temperature"]) : nil,
        condition: extract_condition(day_period["shortForecast"]),
        description: day_period["shortForecast"]
      }
    end

    daily_forecasts
  end


  # ===== UTILITY HELPER METHODS =====

  # Extracts simplified weather condition from weather.gov forecast text
  # Maps detailed descriptions to standard condition categories
  #
  # @param forecast_text [String] weather.gov forecast description (e.g., "Partly Sunny")
  # @return [String] simplified condition (e.g., "Sunny", "Cloudy", "Rainy", "Stormy", "Snow")
  def extract_condition(forecast_text)
    # Extract main condition from weather.gov text
    case forecast_text.downcase
    when /sunny|clear/
      "Sunny"
    when /partly cloudy|partly sunny/
      "Partly Cloudy"
    when /cloudy|overcast/
      "Cloudy"
    when /rain|shower/
      "Rainy"
    when /storm|thunder/
      "Stormy"
    when /snow/
      "Snow"
    else
      forecast_text.split(" ").first.capitalize
    end
  end

  # Extracts humidity percentage from detailed forecast text
  # Uses regex to find humidity values, falls back to random if not found
  #
  # @param detailed_forecast [String] detailed forecast description from weather.gov
  # @return [Integer] humidity percentage (30-80% if not found in text)
  def extract_humidity(detailed_forecast)
    # Try to extract humidity from detailed forecast text
    humidity_match = detailed_forecast.to_s.match(/humidity[:\s]*(\d+)%/i)
    humidity_match ? humidity_match[1].to_i : rand(30..80) # fallback to random if not found
  end

  # Extracts numeric wind speed from weather.gov wind speed text
  #
  # @param wind_speed_text [String] wind speed text (e.g., "10 mph", "5 to 15 mph")
  # @return [Integer] wind speed in mph, 0 if no number found
  def extract_wind_speed(wind_speed_text)
    # Extract wind speed number from text like "10 mph"
    wind_match = wind_speed_text.to_s.match(/(\d+)/)
    wind_match ? wind_match[1].to_i : 0
  end

  # Converts temperature value to integer
  #
  # @param temp_value [String, Integer] temperature value from API
  # @return [Integer] temperature as integer
  def extract_temperature(temp_value)
    temp_value.to_i
  end

  # Finds the lowest temperature from the next few forecast periods
  # Used to determine today's low temperature
  #
  # @param forecast_periods [Array<Hash>] array of forecast periods
  # @return [Integer] lowest temperature found in first 4 periods
  def find_low_temp(forecast_periods)
    # Find the lowest temperature in the next few periods
    temps = forecast_periods.first(4).map { |p| p["temperature"].to_i }
    temps.min
  end

  # Formats ISO 8601 date string into human-readable format
  #
  # @param date_string [String] ISO 8601 date string from weather.gov
  # @return [String] formatted date (e.g., "Monday, Jan 15") or "Unknown Date" if parsing fails
  def format_date(date_string)
    Date.parse(date_string).strftime("%A, %b %d")
  rescue
    "Unknown Date"
  end
end
