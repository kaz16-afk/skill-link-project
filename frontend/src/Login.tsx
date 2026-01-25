import { useState } from 'react';
import { signIn, confirmSignIn } from 'aws-amplify/auth';

interface LoginProps {
  onLoginSuccess: () => void;
}

const Login = ({ onLoginSuccess }: LoginProps) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [newPassword, setNewPassword] = useState(''); // 新パスワード用
  const [isNewPasswordRequired, setIsNewPasswordRequired] = useState(false); // 画面切り替えフラグ
  const [error, setError] = useState('');

  // 1. 通常のログイン試行
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    try {
      const { isSignedIn, nextStep } = await signIn({ username: email, password });

      // パスワード強制変更が必要なステップか確認
      if (nextStep?.signInStep === 'CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED') {
        setIsNewPasswordRequired(true);
        console.log('新パスワードの設定が必要です');
      } else if (isSignedIn) {
        console.log('AWSでのログインに成功しました');
        onLoginSuccess();
      }
    } catch (err: any) {
      console.error('ログインエラー:', err);
      setError('ログインに失敗しました。メールアドレスまたはパスワードを確認してください。');
    }
  };

  // 2. 新しいパスワードの確定処理
  const handleNewPasswordSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    // ★追加: 初期パスワードと新しいパスワードが同じなら弾く
    if (password === newPassword) {
      setError('新しいパスワードは、初期パスワードと異なるものを設定してください。');
      return;
    }

    try {
      // 新しいパスワードを送信して確定させる
      const { isSignedIn } = await confirmSignIn({ challengeResponse: newPassword });
      
      if (isSignedIn) {
        console.log('パスワード更新とログインに成功しました');
        onLoginSuccess();
      }
    } catch (err: any) {
      console.error('パスワード更新エラー:', err);
      // AWSのポリシー（8文字以上など）に引っかかった場合のエラー
      setError('パスワードの更新に失敗しました。8文字以上、英数字を含めて試してください。');
    }
  };

  // --- 画面表示の切り替え ---

  // 新パスワード設定画面
  if (isNewPasswordRequired) {
    return (
      <div style={{ padding: '20px', border: '1px solid #ccc', borderRadius: '8px' }}>
        <h2>新しいパスワードを設定</h2>
        <p style={{ fontSize: '0.9em', color: '#666' }}>初回ログインのため、パスワードの変更が必要です。</p>
        {error && <p style={{ color: 'red' }}>{error}</p>}
        <form onSubmit={handleNewPasswordSubmit}>
          <div>
            <label>新しいパスワード:</label><br />
            <input 
              type="password" 
              value={newPassword} 
              onChange={(e) => setNewPassword(e.target.value)} 
              required 
              placeholder="8文字以上"
            />
          </div>
          <br />
          <button type="submit">パスワードを更新してログイン</button>
        </form>
      </div>
    );
  }

  // 通常のログイン画面
  return (
    <div style={{ padding: '20px', border: '1px solid #ccc', borderRadius: '8px' }}>
      <h2>ログイン</h2>
      {error && <p style={{ color: 'red' }}>{error}</p>}
      <form onSubmit={handleSubmit}>
        <div>
          <label>メールアドレス:</label><br />
          <input 
            type="email" 
            value={email} 
            onChange={(e) => setEmail(e.target.value)} 
            required 
          />
        </div>
        <br />
        <div>
          <label>パスワード:</label><br />
          <input 
            type="password" 
            value={password} 
            onChange={(e) => setPassword(e.target.value)} 
            required 
          />
        </div>
        <br />
        <button type="submit">ログイン</button>
      </form>
    </div>
  );
};

export default Login;
