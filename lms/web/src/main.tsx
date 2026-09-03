import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './components/App'
import { VisibilityProvider } from './providers/VisibilityProvider'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <VisibilityProvider>
      <App />
    </VisibilityProvider>
  </React.StrictMode>,
)
