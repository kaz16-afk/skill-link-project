import React, { useState, useRef } from 'react';
import type { ChangeEvent, DragEvent } from 'react';

// Lambda URL
const LAMBDA_URL = "<ENTER_YOUR_LAMBDA_URL>";

const SkillSheetUpload = () => {
  // 複数ファイルを管理
  const [files, setFiles] = useState<File[]>([]);
  const [uploading, setUploading] = useState<boolean>(false);
  const [message, setMessage] = useState<string>("");
  const [isDragging, setIsDragging] = useState<boolean>(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  // --- ファイル追加・フィルタリング処理 ---
  const addFiles = (newFiles: FileList | null) => {
    if (!newFiles) return;
    
    const fileArray = Array.from(newFiles);
    
    // PDF/Excelのみ許可
    const validFiles = fileArray.filter(file => {
      const name = file.name.toLowerCase();
      return name.endsWith('.pdf') || name.endsWith('.xlsx') || name.endsWith('.xls');
    });

    if (validFiles.length === 0) {
      setMessage("⚠️ PDFまたはExcelファイルのみ対応しています");
      return;
    }

    // 最大10枚制限
    if (validFiles.length > 10) {
      setMessage("⚠️ 一度にアップロードできるのは10枚までです");
      setFiles(validFiles.slice(0, 10));
    } else {
      setFiles(validFiles);
      setMessage(`${validFiles.length}個のファイルを選択しました`);
    }
  };

  const handleFileChange = (e: ChangeEvent<HTMLInputElement>) => {
    addFiles(e.target.files);
  };

  // --- ドラッグ＆ドロップ関連 ---
  const handleDragOver = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragging(false);
  };

  const handleDrop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragging(false);
    addFiles(e.dataTransfer.files);
  };

  const handleClickArea = () => {
    fileInputRef.current?.click();
  };

  // --- 一括アップロード処理 ---
  const handleUpload = async () => {
    if (files.length === 0) {
      setMessage("ファイルを選択してください。");
      return;
    }

    setUploading(true);
    setMessage(`🚀 ${files.length}枚のファイルをアップロード中...`);

    try {
      // 全ファイルを並列処理 (Promise.all)
      const uploadPromises = files.map(async (file) => {
        // 1. 署名付きURL取得
        const queryParams = new URLSearchParams({
          fileName: file.name,
          fileType: file.type 
        });
        const presignRes = await fetch(`${LAMBDA_URL}?${queryParams.toString()}`);
        if (!presignRes.ok) throw new Error(`${file.name}: URL発行エラー`);
        const { uploadUrl } = await presignRes.json();

        // 2. S3アップロード
        const uploadRes = await fetch(uploadUrl, {
          method: "PUT",
          headers: { "Content-Type": file.type },
          body: file,
        });
        if (!uploadRes.ok) throw new Error(`${file.name}: S3送信エラー`);
        
        return file.name;
      });

      // 全て完了するまで待機
      await Promise.all(uploadPromises);

      setMessage(`✅ 完了！ ${files.length}枚のスキルシートを送信しました。`);
      setFiles([]); // クリア
      if (fileInputRef.current) fileInputRef.current.value = ""; 

    } catch (error: any) {
      console.error(error);
      setMessage(`❌ エラー: 一部のファイルで失敗しました (${error.message})`);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div style={styles.container}>
      <h3>📄 スキルシート一括登録</h3>

      <div 
        style={{
          ...styles.dropZone,
          ...(isDragging ? styles.dropZoneActive : {}),
          ...(files.length > 0 ? styles.dropZoneFileSet : {})
        }}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        onClick={handleClickArea}
      >
        <input 
          type="file" 
          accept=".pdf, .xlsx, .xls"
          multiple
          onChange={handleFileChange} 
          style={{ display: 'none' }}
          ref={fileInputRef}
        />
        
        {files.length > 0 ? (
          <div style={{ width: '100%' }}>
            <p style={{ fontSize: '2rem', margin: '10px 0' }}>📚</p>
            <p style={{ fontWeight: 'bold' }}>{files.length} ファイルを選択中</p>
            <ul style={styles.fileList}>
              {files.map((f, i) => (
                <li key={i} style={styles.fileItem}>・{f.name}</li>
              ))}
            </ul>
          </div>
        ) : (
          <div>
            <p style={{ fontSize: '2rem', margin: '10px 0' }}>☁️</p>
            <p>ここにファイルをドラッグ＆ドロップ</p>
            <p style={{ fontSize: '0.8rem', color: '#888' }}>
              (最大10枚まで・Excel / PDF)
            </p>
          </div>
        )}
      </div>

      <button 
        onClick={handleUpload} 
        disabled={files.length === 0 || uploading}
        style={uploading ? styles.buttonDisabled : styles.button}
      >
        {uploading ? "一括送信中..." : "アップロード実行"}
      </button>

      {message && <p style={styles.message}>{message}</p>}
    </div>
  );
};

// スタイル定義 (警告対策済み)
const styles: { [key: string]: React.CSSProperties } = {
  container: {
    padding: '30px',
    border: '1px solid #e0e0e0',
    borderRadius: '12px',
    maxWidth: '500px',
    margin: '40px auto',
    backgroundColor: '#fff',
    boxShadow: '0 4px 12px rgba(0,0,0,0.05)',
    textAlign: 'center',
    color: '#333',
  },
  dropZone: {
    // コンソールの警告対策: borderを一括指定せず分ける
    borderWidth: '2px',
    borderStyle: 'dashed',
    borderColor: '#ccc',
    
    borderRadius: '8px',
    padding: '40px 20px',
    marginBottom: '20px',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    backgroundColor: '#fafafa',
    minHeight: '200px',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    alignItems: 'center',
  },
  dropZoneActive: {
    borderColor: '#007bff',
    backgroundColor: '#e6f7ff',
  },
  dropZoneFileSet: {
    borderColor: '#28a745',
    backgroundColor: '#f0fff4',
    borderStyle: 'solid',
  },
  fileList: {
    listStyle: 'none',
    padding: 0,
    margin: '10px 0',
    fontSize: '0.85rem',
    textAlign: 'left',
    maxHeight: '100px',
    overflowY: 'auto',
    width: '100%',
  },
  fileItem: {
    marginBottom: '4px',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    maxWidth: '100%',
    padding: '2px 5px',
    backgroundColor: '#eee',
    borderRadius: '4px',
  },
  button: {
    width: '100%',
    padding: '12px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '6px',
    fontSize: '16px',
    cursor: 'pointer',
    fontWeight: 'bold',
    transition: 'background 0.2s',
  },
  buttonDisabled: {
    width: '100%',
    padding: '12px',
    backgroundColor: '#ccc',
    color: '#666',
    border: 'none',
    borderRadius: '6px',
    cursor: 'not-allowed',
    fontSize: '16px',
  },
  message: {
    marginTop: '15px',
    fontWeight: 'bold',
    whiteSpace: 'pre-wrap',
    color: '#28a745',
  },
};

export default SkillSheetUpload;