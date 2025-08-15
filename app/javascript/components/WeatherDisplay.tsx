import React from 'react'

interface CurrentWeather {
  temperature: number
  condition: string
  description: string
  humidity: number
  wind_speed: number
  high: number
  low: number
}

interface ForecastDay {
  date: string
  high: number
  low: number
  condition: string
  description: string
}

interface WeatherData {
  address: string
  current: CurrentWeather
  forecast: ForecastDay[]
  from_cache?: boolean
}

interface WeatherDisplayProps {
  weatherData: WeatherData | null
  error: string | null
  onRetry: () => void
}

const WeatherDisplay: React.FC<WeatherDisplayProps> = ({ weatherData, error, onRetry }) => {
  const getWeatherIcon = (condition: string) => {
    const icons: { [key: string]: string } = {
      'Sunny': '☀️',
      'Clear': '☀️',
      'Partly Cloudy': '⛅',
      'Partly Sunny': '⛅',
      'Cloudy': '☁️',
      'Overcast': '☁️',
      'Rainy': '🌧️',
      'Rain': '🌧️',
      'Stormy': '⛈️',
      'Thunderstorm': '⛈️',
      'Snow': '❄️',
      'Snowy': '❄️',
      'Fog': '🌫️',
      'Mist': '🌫️'
    }
    
    return icons[condition] || '🌤️'
  }

  const getTemperatureColor = (temp: number) => {
    if (temp >= 80) return '#ff6b35' // Hot - Orange/Red
    if (temp >= 70) return '#ffa500' // Warm - Orange  
    if (temp >= 60) return '#32cd32' // Mild - Green
    if (temp >= 50) return '#4169e1' // Cool - Blue
    return '#6495ed' // Cold - Light Blue
  }

  const getUserFriendlyError = (errorMessage: string) => {
    if (errorMessage.includes("Address not found")) {
      return {
        title: "Address Not Found",
        message: "We couldn't find that address. Please check your spelling and try again.",
        suggestion: "Try including more details like city, state, or ZIP code."
      }
    }
    
    if (errorMessage.includes("Weather grid not available")) {
      return {
        title: "Location Not Supported",
        message: "Weather data is not available for this location.",
        suggestion: "This service only provides weather for locations within the United States."
      }
    }
    
    if (errorMessage.includes("Weather data not available")) {
      return {
        title: "Weather Data Unavailable",
        message: "We're having trouble getting weather information right now.",
        suggestion: "Please try again in a few moments."
      }
    }
    
    if (errorMessage.includes("Invalid address format")) {
      return {
        title: "Invalid Address",
        message: "The address format appears to be invalid.",
        suggestion: "Please enter a valid US address with street, city, and state."
      }
    }
    
    // Default error for any other cases
    return {
      title: "Something Went Wrong",
      message: "We encountered an unexpected error while getting your weather.",
      suggestion: "Please try again or contact support if the problem persists."
    }
  }

  if (error) {
    const errorInfo = getUserFriendlyError(error)
    
    return (
      <div className="weather-display error">
        <div className="error-icon">⚠️</div>
        <h3>{errorInfo.title}</h3>
        <p className="error-message">{errorInfo.message}</p>
        <p className="error-suggestion">{errorInfo.suggestion}</p>
        <button onClick={onRetry} className="retry-button">
          Try Again
        </button>
      </div>
    )
  }

  if (!weatherData) {
    return null
  }

  const { current, forecast } = weatherData

  return (
    <div className="weather-display">
      {/* Location Header */}
      <div className="location-header">
        <div className="location-icon">📍</div>
        <h3 className="location-title">{weatherData.address}</h3>
        <div className="weather-subtitle">Current Weather Conditions</div>
        {weatherData.from_cache !== undefined && (
          <div className={`cache-indicator ${weatherData.from_cache ? 'cached' : 'live'}`}>
            {weatherData.from_cache ? (
              <>
                <span className="cache-icon">📦</span>
                <span className="cache-text">Cached Result</span>
              </>
            ) : (
              <>
                <span className="cache-icon">🌐</span>
                <span className="cache-text">Live Data</span>
              </>
            )}
          </div>
        )}
      </div>
      
      {/* Current Weather */}
      <div className="current-weather-hero">
        <div className="weather-icon-large">
          {getWeatherIcon(current.condition)}
        </div>
        <div className="temperature-display">
          <span 
            className="temperature-main" 
            style={{ color: getTemperatureColor(current.temperature) }}
          >
            {current.temperature}°
          </span>
          <span className="temperature-unit">F</span>
        </div>
        <div className="condition-main">{current.condition}</div>
        <div className="condition-description">{current.description}</div>
      </div>

      {/* Today's Details */}
      <div className="today-details">
        <div className="detail-card">
          <div className="detail-icon">🌡️</div>
          <div className="detail-content">
            <div className="detail-label">High / Low</div>
            <div className="detail-value">{current.high}° / {current.low}°</div>
          </div>
        </div>
        
        <div className="detail-card">
          <div className="detail-icon">💧</div>
          <div className="detail-content">
            <div className="detail-label">Humidity</div>
            <div className="detail-value">{current.humidity}%</div>
          </div>
        </div>
        
        <div className="detail-card">
          <div className="detail-icon">💨</div>
          <div className="detail-content">
            <div className="detail-label">Wind Speed</div>
            <div className="detail-value">{current.wind_speed} mph</div>
          </div>
        </div>
      </div>

      {/* 7-Day Forecast */}
      <div className="forecast-section">
        <h4 className="forecast-title">
          <span className="forecast-icon">📅</span>
          7-Day Forecast
        </h4>
        <div className="forecast-grid">
          {forecast.map((day, index) => (
            <div key={index} className="forecast-day">
              <div className="day-name">{day.date}</div>
              <div className="day-weather-icon">{getWeatherIcon(day.condition)}</div>
              <div className="day-condition">{day.condition}</div>
              <div className="day-temps">
                <span className="high">{day.high}°</span>
                <span className="low">{day.low}°</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

export default WeatherDisplay