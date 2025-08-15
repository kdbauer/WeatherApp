# Weather Forecast Application

A modern Ruby on Rails 8 web application that provides weather forecasts for any address in the United States. Built with React frontend, Redis caching, and integration with the National Weather Service API.

## 🌤️ What This Application Does

This weather application accepts any US address as input and displays comprehensive weather information including:

- **Current Weather Conditions** - Temperature, humidity, wind speed, and weather description
- **Daily High/Low Temperatures** - Today's temperature range
- **7-Day Extended Forecast** - Complete week-ahead weather outlook
- **Smart Caching** - Results cached for 30 minutes to reduce API calls and improve performance
- **Cache Indicators** - Visual indication when data is served from cache vs. live API

The application integrates with two government APIs:
1. **Census Geocoding API** - Converts addresses to precise latitude/longitude coordinates
2. **National Weather Service API** - Provides official weather data for the United States

## 🚀 Installation & Setup

### Prerequisites

- **Ruby**: 3.2.2 (managed via rbenv)
- **Node.js**: 18+ (for Vite and React)
- **Redis**: 6+ (for caching)

### Local Development Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd weather_app
   ```

2. **Install Ruby dependencies**
   ```bash
   bundle install
   ```

3. **Install Node.js dependencies**
   ```bash
   npm install
   ```

4. **Start Redis server**
   ```bash
   # macOS with Homebrew
   brew services start redis
   
   # Or manually
   redis-server
   ```

5. **Verify Redis is running**
   ```bash
   redis-cli ping
   # Should respond with: PONG
   ```

## 🏃‍♂️ Running the Application

### Development Server

Start the Rails server with Vite for hot reloading:

```bash
bin/dev
```

The application will be available at: `http://localhost:3000`

## 🧪 Running Tests

### Full Test Suite
```bash
# Run all RSpec tests
bundle exec rspec
```

### Specific Test Files
```bash
# Test WeatherService
bundle exec rspec spec/services/weather_service_spec.rb

# Test WeatherController
bundle exec rspec spec/controllers/weather_controller_spec.rb
```

### Code Quality
```bash
# Run RuboCop linter
bundle exec rubocop
```

## 🔍 Viewing Redis Cache Data

### Connect to Redis CLI
```bash
redis-cli
```

### Common Redis Commands
```bash
# List all weather cache keys
KEYS weather_forecast:*

# View specific cached forecast
GET weather_forecast:12345

# Check TTL (time to live) for a key
TTL weather_forecast:12345

# View all keys and their TTL
SCAN 0 MATCH weather_forecast:*

# Clear all weather cache
FLUSHDB
```

### Monitor Redis Activity
```bash
# Watch Redis commands in real-time
redis-cli MONITOR
```

## 🏗️ Key Architecture Components

### 1. WeatherService (`app/services/weather_service.rb`)

The core service class that orchestrates weather data retrieval with intelligent caching.

**Key Features:**
- **Persistent HTTP Connections** - Uses `HTTP.persistent` for efficient API calls
- **Error Handling** - Comprehensive error handling with user-friendly messages
- **Data Transformation** - Converts raw API responses into structured, frontend-ready data
- **Geocoding Integration** - Converts addresses to coordinates via Census API
- **Weather Grid Resolution** - Retrieves National Weather Service grid points for accurate forecasts

**API Integration Flow:**
```
Address Input → Census Geocoding → Weather.gov Grid → Current Conditions + 7-Day Forecast
```

### 2. Redis Caching System

**Cache Strategy:**
- **Cache Key Format**: `weather_forecast:{zip_code}`
- **TTL (Time To Live)**: 30 minutes (1800 seconds)
- **Cache Hit Indicator**: `from_cache: true` flag in API responses
- **Fallback Behavior**: If Redis is unavailable, the app continues without caching

**Cache Benefits:**
- **Reduced API Calls** - Minimizes requests to government APIs
- **Improved Performance** - Sub-millisecond cache retrieval vs. multi-second API calls
- **Rate Limit Protection** - Prevents hitting API rate limits during high usage

**Implementation Details:**
- Zip code extraction from formatted addresses for consistent cache keys
- Automatic cache invalidation after 30 minutes
- Graceful degradation when Redis is unavailable

### 3. React Frontend (`app/javascript/`)

**Modern React Architecture:**
- **TypeScript Integration** - Type-safe component development
- **Component Structure**:
  - `App.tsx` - Main application state and API communication
  - `WeatherForm.tsx` - Address input with validation
  - `WeatherDisplay.tsx` - Weather data presentation with error handling
- **Vite Integration** - Fast development builds and hot module replacement

**Frontend Features:**
- **Responsive Design** - Mobile-first CSS with desktop enhancements
- **Weather Icons** - Visual weather condition indicators
- **Error Handling** - User-friendly error messages with retry functionality
- **Cache Indicators** - Visual badges showing data source (live vs. cached)
- **Loading States** - Smooth UX during API calls

## 🎯 Design Choices & Implementation Rationale

### API Selection: Government APIs vs. Commercial Services

**Decision**: Use Census Geocoding API + National Weather Service API instead of commercial services (OpenWeatherMap, etc.)

**Rationale**:
- **Cost Efficiency** - Government APIs are free with no rate limits for reasonable usage
- **Data Accuracy** - National Weather Service provides the most accurate US weather data
- **Reliability** - Government APIs have high uptime and are maintained long-term
- **No API Key Management** - Eliminates the complexity of API key rotation and billing

### Caching Strategy: Redis with Zip Code Keys

**Decision**: Cache by zip code rather than full address with 30-minute TTL

**Rationale**:
- **Optimal Cache Hit Rate** - Multiple addresses in the same zip code share cache entries
- **Reasonable Freshness** - 30 minutes balances data freshness with API efficiency
- **Geographic Accuracy** - Weather conditions are consistent within zip code boundaries
- **Storage Efficiency** - Zip codes create fewer, more reusable cache entries

### Frontend Architecture: Rails + React with Vite

**Decision**: Use Rails as API backend with React frontend instead of full Rails views

**Rationale**:
- **Modern UX** - React provides smooth, interactive user experience
- **Development Speed** - Vite offers instant hot reloading during development
- **Separation of Concerns** - Clean API/frontend separation enables future mobile apps
- **Type Safety** - TypeScript prevents runtime errors and improves developer experience

### Error Handling: User-Friendly Messages

**Decision**: Transform technical API errors into user-friendly messages

**Rationale**:
- **Better UX** - Users see "Address not found" instead of "HTTP 404 Error"
- **Actionable Feedback** - Error messages guide users toward successful inputs
- **Retry Functionality** - Users can easily retry failed requests
- **Graceful Degradation** - App remains functional even when external APIs fail

### HTTP Client: Persistent Connections

**Decision**: Use `HTTP.persistent` instead of standard HTTP clients

**Rationale**:
- **Performance Optimization** - Reuses TCP connections for multiple API calls
- **Reduced Latency** - Eliminates connection handshake overhead
- **Resource Efficiency** - Lower memory and CPU usage for repeated requests
- **Production Ready** - Handles connection pooling and cleanup automatically

### Database Architecture: No Persistent Storage

**Decision**: Use Redis-only caching without database tables for weather data

**Rationale**:
- **Ephemeral Data Nature** - Weather data becomes stale quickly and doesn't need long-term storage
- **External API as Source of Truth** - National Weather Service API provides authoritative, up-to-date data
- **Simplified Architecture** - Eliminates database migrations, schema management, and data synchronization
- **Cost Efficiency** - No database storage costs or backup requirements for transient data
- **Cache-First Strategy** - Redis TTL naturally handles data freshness without manual cleanup

**When a Database Would Be Beneficial**:

*User Management & Personalization:*
- User accounts with saved favorite locations
- Personal weather preferences and alert settings
- Historical search patterns and location bookmarks

*Analytics & Business Intelligence:*
- Track popular search locations and usage patterns
- Store weather request logs for performance analysis
- Generate reports on API usage and cache hit rates

*Enhanced Features:*
- Weather alerts and notifications based on user preferences
- Historical weather data comparison and trends
- Custom weather dashboards with multiple saved locations

*Compliance & Auditing:*
- Request logging for debugging and monitoring
- User activity tracking for security purposes
- API usage metrics for rate limiting and billing

**Current Architecture Benefits**:
- **Faster Development** - No schema design or migration management
- **Stateless Design** - Easy horizontal scaling and deployment
- **Data Freshness** - Always serves current weather without stale database records
- **Reduced Complexity** - Fewer moving parts and potential failure points

## 🔧 Development Tools

- **Testing**: RSpec with FactoryBot, WebMock, and VCR
- **Code Quality**: RuboCop for Ruby style enforcement
- **Frontend**: Vite + React 19 + TypeScript
- **HTTP Client**: `http` gem with persistent connections
- **Caching**: Redis with automatic failover

---
