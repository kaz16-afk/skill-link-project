import React, { useState } from 'react';
import { signIn, confirmSignIn } from 'aws-amplify/auth';
// ▼▼▼ 画像をインポート
import logoImg from './assets/logo.jpg'; 
// ▲▲▲ 画像をインポート ▲▲▲

interface LoginProps {
  onLoginSuccess: () => void;
}

const Login = ({ onLoginSuccess }: LoginProps) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [isNewPasswordRequired, setIsNewPasswordRequired] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    try {
      const { isSignedIn, nextStep } = await signIn({ username: email, password });
      if (nextStep?.signInStep === 'CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED') {
        setIsNewPasswordRequired(true);
      } else if (isSignedIn) {
        onLoginSuccess();
      }
    } catch (err: any) {
      console.error('Login Error:', err);
      setError('ログインに失敗しました。');
    }
  };

  const handleNewPasswordSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (password === newPassword) {
      setError('新しいパスワードは、初期パスワードと異なるものを設定してください。');
      return;
    }
    try {
      const { isSignedIn } = await confirmSignIn({ challengeResponse: newPassword });
      if (isSignedIn) onLoginSuccess();
    } catch (err: any) {
      setError('パスワード更新エラー: ' + err.message);
    }
  };

  // 共通のヘッダー部分（ロゴ + タイトル）
  const LoginHeader = ({ title }: { title: string }) => (
    <>
      {/* ▼▼▼ ロゴ画像を表示 ▼▼▼ */}
      <img src={logoImg} className="app-logo" alt="SKiLL-LiNK Logo" />
      {/* ▲▲▲ ロゴ画像を表示 ▲▲▲ */}
      <h2>{title}</h2>
    </>
  );

  if (isNewPasswordRequired) {
    return (
      <div className="login-card">
        <LoginHeader title="新しいパスワード設定" />
        <p style={{ fontSize: '0.9em', color: '#666', textAlign: 'center', marginBottom: '20px' }}>
          初回ログインのため変更が必要です
        </p>
        {error && <p className="error-msg">{error}</p>}
        <form onSubmit={handleNewPasswordSubmit}>
          <label>新しいパスワード</label>
          <input 
            type="password" 
            value={newPassword} 
            onChange={(e) => setNewPassword(e.target.value)} 
            required 
            placeholder="8文字以上"
          />
          <button type="submit">更新してログイン</button>
        </form>
      </div>
    );
  }

  return (
    <div className="login-card">
      {/* ▼ タイトルを変更 ▼ */}
      <LoginHeader title="SKiLL-LiNK" />
      {error && <p className="error-msg">{error}</p>}
      <form onSubmit={handleSubmit}>
        <label>メールアドレス</label>
        <input 
          type="email" 
          value={email} 
          onChange={(e) => setEmail(e.target.value)} 
          required 
          placeholder="example@company.com"
        />
        <label>パスワード</label>
        <input 
          type="password" 
          value={password} 
          onChange={(e) => setPassword(e.target.value)} 
          required 
        />
        <button type="submit">ログイン</button>
      </form>
    </div>
  );
};

export default Login;