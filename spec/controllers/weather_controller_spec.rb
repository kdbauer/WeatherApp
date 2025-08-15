require 'rails_helper'

RSpec.describe WeatherController, type: :controller do
  let(:valid_address) { "1600 Pennsylvania Ave NW, Washington, DC" }
  let(:invalid_address) { "Invalid@Address#123!" }
  let(:empty_address) { "" }
  let(:long_address) { "A" * 201 } # Over 200 character limit
  let(:short_address) { "AB" } # Under 3 character minimum

  let(:successful_weather_data) do
    {
      address: "1600 PENNSYLVANIA AVE NW, WASHINGTON, DC, 20500",
      current: {
        temperature: 72,
        condition: "Partly Cloudy",
        description: "Partly cloudy skies",
        humidity: 65,
        wind_speed: 10,
        high: 78,
        low: 62
      },
      forecast: [
        {
          date: "Monday, Jan 15",
          high: 78,
          low: 62,
          condition: "Sunny",
          description: "Sunny skies"
        }
      ],
      from_cache: false
    }
  end

  let(:weather_service_error_data) do
    { error: "Address not found" }
  end

  describe "GET #index" do
    it "returns http success" do
      get :index
      expect(response).to have_http_status(:success)
    end

    it "renders the index template" do
      get :index
      expect(response).to render_template(:index)
    end
  end

  describe "POST #show" do
    let(:weather_service) { instance_double(WeatherService) }

    before do
      allow(WeatherService).to receive(:new).and_return(weather_service)
    end

    context "with valid nested parameters and successful service call" do
      let(:valid_params) do
        {
          weather: {
            address: valid_address
          }
        }
      end

      before do
        allow(weather_service).to receive(:get_weather_forecast)
          .with(valid_address)
          .and_return(successful_weather_data)
      end

      it "returns http success" do
        post :show, params: valid_params
        expect(response).to have_http_status(:success)
      end

      it "returns JSON response with weather data" do
        post :show, params: valid_params

        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          "address" => "1600 PENNSYLVANIA AVE NW, WASHINGTON, DC, 20500",
          "current" => hash_including("temperature" => 72),
          "forecast" => array_including(hash_including("date" => "Monday, Jan 15")),
          "from_cache" => false
        )
      end

      it "calls WeatherService with correct address" do
        expect(weather_service).to receive(:get_weather_forecast).with(valid_address)
        post :show, params: valid_params
      end

      it "returns correct content type" do
        post :show, params: valid_params
        expect(response.content_type).to include("application/json")
      end
    end

    context "with missing weather parameter" do
      it "returns 400 error for missing weather key" do
        post :show, params: { address: valid_address }

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Address parameter is required")
      end
    end

    context "with missing address parameter" do
      it "returns 400 error for missing address key" do
        post :show, params: { weather: {} }

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Address parameter is required")
      end
    end

    context "with invalid address formats" do
      let(:invalid_params) do
        {
          weather: {
            address: invalid_address
          }
        }
      end

      it "returns 400 error for address with invalid characters" do
        post :show, params: invalid_params

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid address format")
      end

      it "returns 400 error for empty address" do
        post :show, params: { weather: { address: empty_address } }

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid address format")
      end

      it "returns 400 error for address too long" do
        post :show, params: { weather: { address: long_address } }

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid address format")
      end

      it "returns 400 error for address too short" do
        post :show, params: { weather: { address: short_address } }

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid address format")
      end
    end

    context "when WeatherService returns an error" do
      let(:valid_params) do
        {
          weather: {
            address: valid_address
          }
        }
      end

      before do
        allow(weather_service).to receive(:get_weather_forecast)
          .with(valid_address)
          .and_return(weather_service_error_data)
      end

      it "returns 400 error with service error message" do
        post :show, params: valid_params

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Address not found")
      end
    end

    context "when WeatherService raises an exception" do
      let(:valid_params) do
        {
          weather: {
            address: valid_address
          }
        }
      end

      let(:service_exception) { StandardError.new("Connection timeout") }

      before do
        allow(weather_service).to receive(:get_weather_forecast)
          .with(valid_address)
          .and_raise(service_exception)
      end

      it "handles service exceptions gracefully" do
        post :show, params: valid_params

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Service error: Connection timeout")
      end
    end

    context "with cached weather data" do
      let(:valid_params) do
        {
          weather: {
            address: valid_address
          }
        }
      end

      let(:cached_weather_data) do
        successful_weather_data.merge(from_cache: true)
      end

      before do
        allow(weather_service).to receive(:get_weather_forecast)
          .with(valid_address)
          .and_return(cached_weather_data)
      end

      it "returns cached data with from_cache flag" do
        post :show, params: valid_params

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["from_cache"]).to be true
      end
    end

    context "parameter security" do
      it "only permits address parameter from weather hash" do
        unpermitted_params = {
          weather: {
            address: valid_address,
            malicious_param: "hacker_data",
            admin: true
          },
          other_param: "should_be_ignored"
        }

        allow(weather_service).to receive(:get_weather_forecast)
          .with(valid_address)
          .and_return(successful_weather_data)

        post :show, params: unpermitted_params

        expect(response).to have_http_status(:success)
        # Should still work because only address is permitted
      end
    end

    context "CSRF token handling" do
      it "enforces CSRF verification for show action" do
        # Mock the weather service for this test
        allow(weather_service).to receive(:get_weather_forecast)
          .with(valid_address)
          .and_return(successful_weather_data)

        # This test ensures CSRF verification is enabled (security best practice)
        expect(controller).to receive(:verify_authenticity_token).and_call_original

        post :show, params: { weather: { address: valid_address } }
      end
    end
  end

  describe "private methods" do
    describe "#valid_address?" do
      it "returns true for valid addresses" do
        valid_addresses = [
          "123 Main St, Anytown, USA",
          "1600 Pennsylvania Ave NW, Washington, DC",
          "42 Wallaby Way, Sydney",
          "123-456 Oak Street, Unit 7B"
        ]

        valid_addresses.each do |address|
          expect(controller.send(:valid_address?, address)).to be true
        end
      end

      it "returns false for invalid addresses" do
        invalid_addresses = [
          "",                           # Empty
          "AB",                        # Too short
          "A" * 201,                   # Too long
          "123 Main@Street!",          # Invalid characters (@, !)
          "Address with <script>",     # HTML/Script tags (<, >)
          "Address with 中文",          # Non-Latin characters
          "Address#with#hash",         # Hash symbols
          "Address$with$dollar",       # Dollar signs
          "Address&with&ampersand",    # Ampersands
          "Address*with*asterisk",     # Asterisks
          "Address(with)parens",       # Parentheses
          "Address[with]brackets",     # Brackets
          "Address\nwith\nnewlines",   # Newlines (now rejected)
          "Address\twith\ttabs",       # Tabs (now rejected)
          "Address\r\nwith\r\ncarriage" # Carriage returns (now rejected)
        ]

        invalid_addresses.each do |address|
          expect(controller.send(:valid_address?, address)).to be(false),
            "Expected '#{address}' to be invalid but it was valid"
        end
      end

      it "handles nil address" do
        expect(controller.send(:valid_address?, nil)).to be false
      end

      it "only allows regular spaces, not other whitespace characters" do
        # The regex now uses literal space instead of \s to be more restrictive
        valid_with_spaces = [
          "123 Main Street",           # Regular spaces (allowed)
          "Apt 5B, Building A",        # Multiple regular spaces (allowed)
          "123  Main  Street"          # Multiple consecutive spaces (allowed)
        ]

        valid_with_spaces.each do |address|
          expect(controller.send(:valid_address?, address)).to be true
        end
      end
    end

    describe "#weather_params" do
      let(:mock_params) do
        ActionController::Parameters.new({
          weather: {
            address: "123 Main St",
            malicious_param: "should_be_filtered"
          },
          other_param: "should_be_ignored"
        })
      end

      before do
        allow(controller).to receive(:params).and_return(mock_params)
      end

      it "only permits address from weather hash" do
        permitted_params = controller.send(:weather_params)

        expect(permitted_params.keys).to contain_exactly("address")
        expect(permitted_params["address"]).to eq("123 Main St")
      end

      it "raises ParameterMissing when weather key is missing" do
        params_without_weather = ActionController::Parameters.new({
          address: "123 Main St"
        })
        allow(controller).to receive(:params).and_return(params_without_weather)

        expect {
          controller.send(:weather_params)
        }.to raise_error(ActionController::ParameterMissing)
      end
    end
  end

  describe "integration scenarios" do
    context "typical user workflow" do
      let(:integration_weather_service) { instance_double(WeatherService) }

      it "handles complete success flow" do
        allow(WeatherService).to receive(:new).and_return(integration_weather_service)
        allow(integration_weather_service).to receive(:get_weather_forecast)
          .with(valid_address)
          .and_return(successful_weather_data)

        post :show, params: { weather: { address: valid_address } }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        # Verify complete response structure
        expect(json_response).to have_key("address")
        expect(json_response).to have_key("current")
        expect(json_response).to have_key("forecast")
        expect(json_response["current"]).to have_key("temperature")
        expect(json_response["forecast"]).to be_an(Array)
        expect(json_response["forecast"].first).to have_key("date")
      end
    end

    context "error recovery scenarios" do
      it "provides helpful error messages for common mistakes" do
        # Test various error scenarios that users might encounter
        error_scenarios = [
          {
            params: { address: valid_address },
            expected_error: "Address parameter is required",
            description: "missing weather wrapper"
          },
          {
            params: { weather: { addr: valid_address } },
            expected_error: "Invalid address format",
            description: "misspelled address key (gets nil, fails validation)"
          },
          {
            params: { weather: { address: "" } },
            expected_error: "Invalid address format",
            description: "empty address"
          }
        ]

        error_scenarios.each do |scenario|
          post :show, params: scenario[:params]

          expect(response).to have_http_status(:bad_request)
          json_response = JSON.parse(response.body)
          expect(json_response["error"]).to eq(scenario[:expected_error]),
          "Failed for #{scenario[:description]}: expected '#{scenario[:expected_error]}' but got '#{json_response["error"]}'"
        end
      end
    end
  end
end
