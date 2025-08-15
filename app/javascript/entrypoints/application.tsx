import React from 'react'
import { createRoot } from 'react-dom/client'
import App from '../components/App'
import '../styles/application.css'

console.log('Vite ⚡️ Rails with React')

// Mount React app
const container = document.getElementById('root')
if (container) {
  const root = createRoot(container)
  root.render(<App />)
}
