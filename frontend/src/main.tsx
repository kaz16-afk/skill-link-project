import { Amplify } from 'aws-amplify';
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// ★デバッグ用：読み込んだ値をブラウザのコンソールに表示
console.log("--------------------------------------------------");
console.log("Debug: .env Check");
console.log("UserPool ID:", import.meta.env.VITE_COGNITO_USER_POOL_ID);
console.log("Client ID:  ", import.meta.env.VITE_COGNITO_CLIENT_ID);
console.log("--------------------------------------------------");

Amplify.configure({
  Auth: {
    Cognito: {
      // 環境変数から読み込む
      userPoolId: import.meta.env.VITE_COGNITO_USER_POOL_ID,
      userPoolClientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
    }
  }
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)