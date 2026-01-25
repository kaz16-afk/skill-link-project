import { useState, useEffect } from 'react';
import { getCurrentUser, signOut } from 'aws-amplify/auth'; //AWS認証機能のインポート
import Login from './Login';
import SkillSheetUpload from './SkillSheetUpload';
import './App.css';

function App() {
  // 初期値は false (未ログイン) に設定
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  // 認証チェック中かどうかの判定フラグ (チラつき防止用)
  const [isLoading, setIsLoading] = useState(true);

  // 1. アプリ起動時に一度だけ実行：AWSに「今ログインしてる？」と聞く
  useEffect(() => {
    checkAuthStatus();
  }, []);

  const checkAuthStatus = async () => {
    try {
      // 現在のユーザー情報を取得できれば、ログイン済みとみなす
      await getCurrentUser();
      setIsLoggedIn(true);
    } catch (error) {
      // 取得できなければ未ログイン
      setIsLoggedIn(false);
    } finally {
      // チェック完了（ロード画面を消す）
      setIsLoading(false);
    }
  };

  // ログインコンポーネントから呼ばれる関数
  const handleLoginSuccess = () => {
    setIsLoggedIn(true);
  };

  // 2. ログアウト処理
  const handleLogout = async () => {
    try {
      await signOut(); // ブラウザに残っている認証情報を削除
      setIsLoggedIn(false);
    } catch (error) {
      console.error("ログアウトエラー", error);
    }
  };

  // 認証チェック中は「読み込み中」を表示（これがないと一瞬ログイン画面が映ってしまう）
  if (isLoading) {
    return <div style={{ marginTop: '50px' }}>読み込み中...</div>;
  }

  return (
    <div className="App">
      <h1>SKiLL-LiNK ログイン</h1>
      
      {/* ログイン状態によって表示を切り替える */}
      {!isLoggedIn ? (
        <Login onLoginSuccess={handleLoginSuccess} />
      ) : (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <h2>エンジニア スキルシートアップロード画面</h2>
            {/* handleLogout を呼ぶように変更 */}
            <button onClick={handleLogout}>ログアウト</button>
          </div>
          
          <hr />
          
          {/* アップロード部品 */}
          <SkillSheetUpload />
          
        </div>
      )}
    </div>
  );
}

export default App;