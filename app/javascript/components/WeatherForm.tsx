import React, { useState } from 'react'

interface WeatherFormProps {
  onSubmit: (address: string) => void
  loading: boolean
}

const WeatherForm: React.FC<WeatherFormProps> = ({ onSubmit, loading }) => {
  const [address, setAddress] = useState('')

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (address.trim()) {
      onSubmit(address.trim())
    }
  }

  return (
    <form onSubmit={handleSubmit} className="weather-form">
      <div className="form-group">
        <label htmlFor="address">Enter Address:</label>
        <input
          type="text"
          id="address"
          value={address}
          onChange={(e) => setAddress(e.target.value)}
          placeholder="e.g., New York, NY"
          disabled={loading}
          required
        />
      </div>
      <button type="submit" disabled={loading || !address.trim()}>
        {loading ? 'Getting Weather...' : 'Get Weather'}
      </button>
    </form>
  )
}

export default WeatherForm