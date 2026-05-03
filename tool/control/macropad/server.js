const express = require('express');
const { keyboard, Key } = require('@nut-tree/nut-js');
const path = require('path');
const cors = require('cors');

const app = express();
// 使用するポート番号（変更可能）
const port = 3000;

// ミドルウェアの設定
app.use(cors());
app.use(express.json());

// 'public' フォルダの中にあるHTMLや静的ファイルを返すように設定
// これにより、タブレットから http://<PCのIP>:3000/ にアクセスすると index.html が表示されます
app.use(express.static(path.join(__dirname, 'public')));

// ブラウザからのショートカット実行リクエストを受け取るAPIエンドポイント
app.post('/api/shortcut', async (req, res) => {
    // UI側からは配列の配列形式でキーの組み合わせが送られてきます
    // 例: [ ["LeftControl", "C"] ]
    const { sequence } = req.body;
    console.log(`Received sequence:`, sequence);

    try {
        if (!sequence || !Array.isArray(sequence)) {
            return res.status(400).json({ success: false, error: 'Invalid sequence format' });
        }

        // sequence配列を順番に処理（マクロのような連続操作にも対応可能な設計）
        for (const keys of sequence) {
            // 文字列(例: 'LeftControl') から nut.js の Key オブジェクトに変換
            const nutKeys = keys.map(k => Key[k]).filter(k => k !== undefined);
            
            if (nutKeys.length > 0) {
                // 指定されたキーを同時に押下
                await keyboard.type(...nutKeys);
                // 連続入力時の安定性のため、少し待機 (50ミリ秒)
                await new Promise(resolve => setTimeout(resolve, 50));
            }
        }
        
        res.json({ success: true });
    } catch (error) {
        console.error('Error executing shortcut:', error);
        res.status(500).json({ success: false, error: error.message });
    }
});

// '0.0.0.0' を指定することで、ローカルネットワーク内の他の端末（タブレット等）からのアクセスを許可します
app.listen(port, '0.0.0.0', () => {
    console.log(`🚀 Web Macro Pad Server is running!`);
    console.log(`➡️  Access URL from your tablet: http://<Your-PC-IP-Address>:${port}`);
    console.log(`(Press Ctrl+C in this terminal to stop the server)`);
});
