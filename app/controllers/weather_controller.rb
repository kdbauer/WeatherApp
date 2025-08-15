# Weather Controller for handling weather forecast requests
# Serves as the main API interface between the React frontend and WeatherService
# Provides both the main application view and weather data retrieval endpoints
class WeatherController < ApplicationController
  # Renders the main weather application page with React root container
  # This action serves the homepage where users can input addresses and view weather data
  #
  # @return [void] renders the index view with React mounting point
  def index
  end

  # Retrieves weather forecast data for a given address via POST request
  # Accepts nested address parameter, validates input, and returns JSON weather data
  # Integrates with WeatherService for external API calls and Redis caching
  #
  # @param weather [Hash] nested parameter hash containing address
  # @option weather [String] :address the street address to get weather for
  # @return [JSON] weather forecast data with complete object decomposition:
  #   SUCCESS RESPONSE (HTTP 200):
  #   - address [String] formatted/standardized address from Census API
  #   - current [Hash] current weather conditions object:
  #     - temperature [Integer] current temperature in Fahrenheit
  #     - condition [String] simplified weather condition ("Sunny", "Cloudy", etc.)
  #     - description [String] detailed weather description from weather.gov
  #     - humidity [Integer] humidity percentage (0-100)
  #     - wind_speed [Integer] wind speed in mph
  #     - high [Integer] today's high temperature in Fahrenheit
  #     - low [Integer] today's low temperature in Fahrenheit
  #   - forecast [Array<Hash>] 7-day forecast array, each day containing:
  #     - date [String] formatted date ("Monday, Jan 15")
  #     - high [Integer] daily high temperature in Fahrenheit
  #     - low [Integer, nil] daily low temperature in Fahrenheit (nil if unavailable)
  #     - condition [String] simplified weather condition
  #     - description [String] detailed forecast description
  #   - from_cache [Boolean] true if data retrieved from Redis cache, false if fresh API call
  #   ERROR RESPONSE (HTTP 400):
  #   - error [String] user-friendly error message describing the failure
  #
  # @example Successful request body:
  #   POST /weather/show
  #   Content-Type: application/json
  #   {"weather": {"address": "1600 Pennsylvania Ave, Washington DC"}}
  #
  # @example Error scenarios:
  #   - Missing address parameter: {"error": "Address parameter is required"}
  #   - Invalid address format: {"error": "Invalid address format"}
  #   - Service failure: {"error": "Service error: Unable to fetch weather data"}
  def show
    # Extract and validate address parameter using strong parameters
    begin
      address = weather_params[:address]
    rescue ActionController::ParameterMissing => e
      return render json: { error: "Address parameter is required" }, status: 400
    end

    # Perform additional address format validation
    unless valid_address?(address)
      return render json: { error: "Invalid address format" }, status: 400
    end

    # Retrieve weather data via WeatherService with comprehensive error handling
    begin
      weather_service = WeatherService.new
      weather_data = weather_service.get_weather_forecast(address)
    rescue => e
      weather_data = { error: "Service error: #{e.message}" }
    end

    # Return appropriate JSON response based on service result
    if weather_data[:error]
      render json: { error: weather_data[:error] }, status: 400
    else
      render json: weather_data
    end
  end

  private

  # Strong parameters method to whitelist and validate request parameters
  # Enforces nested parameter structure for security and consistency
  # Only accepts address parameter within weather namespace
  #
  # @return [ActionController::Parameters] permitted parameters containing address
  # @raise [ActionController::ParameterMissing] if weather parameter is missing
  # @example Expected parameter structure:
  #   params = {"weather" => {"address" => "123 Main St, City, State"}}
  #   weather_params #=> <ActionController::Parameters {"address"=>"123 Main St, City, State"} permitted: true>
  def weather_params
    params.require(:weather).permit(:address)
  end

  # Validates address format and content for security and data quality
  # Implements multiple validation layers to prevent malicious input and ensure geocoding success
  # Uses restrictive regex to allow only standard address characters
  #
  # @param address [String] the address string to validate
  # @return [Boolean] true if address passes all validation checks, false otherwise
  #
  # @example Valid addresses:
  #   valid_address?("123 Main Street, Anytown, ST 12345") #=> true
  #   valid_address?("1600 Pennsylvania Ave, Washington DC") #=> true
  #
  # @example Invalid addresses:
  #   valid_address?("") #=> false (blank)
  #   valid_address?("ab") #=> false (too short)
  #   valid_address?("address with\nnewline") #=> false (invalid characters)
  #   valid_address?("address<script>alert('xss')</script>") #=> false (invalid characters)
  #
  # Validation Rules:
  # - Must not be blank or nil
  # - Must be between 3 and 200 characters (reasonable address length bounds)
  # - Must contain only: letters, numbers, spaces, commas, periods, hyphens
  # - Uses literal space character (not \s) to exclude tabs, newlines, etc.
  # - Anchored regex (^A and \z) ensures entire string matches pattern
  def valid_address?(address)
    return false if address.blank?
    return false if address.length > 200
    return false if address.length < 3

    # Check for basic address-like content (letters, numbers, regular spaces, commas, periods, hyphens)
    # Note: Using literal space instead of \s to exclude newlines, tabs, etc.
    return false unless address.match?(/\A[a-zA-Z0-9 ,.-]+\z/)

    true
  end
end
