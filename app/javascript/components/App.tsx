import React, { useState } from 'react'
import WeatherForm from './WeatherForm'
import WeatherDisplay from './WeatherDisplay'

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

const App: React.FC = () => {
  const [weatherData, setWeatherData] = useState<WeatherData | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [lastAddress, setLastAddress] = useState<string>('')

  const handleWeatherSubmit = async (address: string) => {
    setLastAddress(address)
    setLoading(true)
    setError(null)
    setWeatherData(null)

    try {
      const response = await fetch('/weather/show', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
        },
        body: JSON.stringify({ weather: { address } })
      })

      if (response.ok) {
        const data = await response.json()
        setWeatherData(data)
      } else {
        const errorData = await response.json()
        setError(errorData.error || 'Failed to fetch weather data')
      }
    } catch (err) {
      setError('Network error. Please check your connection and try again.')
    } finally {
      setLoading(false)
    }
  }

  const handleRetry = () => {
    if (lastAddress) {
      handleWeatherSubmit(lastAddress)
    }
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1>Weather App</h1>
        <p>Get weather information for any address</p>
      </header>
      <main>
        <WeatherForm onSubmit={handleWeatherSubmit} loading={loading} />
        <WeatherDisplay weatherData={weatherData} error={error} onRetry={handleRetry} />
      </main>
    </div>
  )
}

export default App