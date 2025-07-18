# Scale API

Scale APIは、Azure Kubernetes Service (AKS) のDeploymentをScale to ZeroするためのシンプルなREST APIです。

## 機能

- Deploymentのレプリカ数を0にスケール（Scale to Zero）
- Deploymentを指定したレプリカ数にスケールアップ
- Deploymentの現在のステータス確認
- APIキー認証（オプション）
- 構造化ログ出力
- ヘルスチェックエンドポイント

## クイックスタート

### 開発環境での実行

```bash
# 依存関係のインストール
make deps

# ビルド
make build

# 開発モードで実行
make run-dev

# API認証を有効にして実行
make run-auth
```

### テスト

```bash
# すべてのテストを実行
make test

# ユニットテストのみ
make test-unit

# 統合テスト
make test-integration

# カバレッジレポート生成
make test-coverage
```

### 統合テストスクリプト

```bash
# 統合テストスクリプトを実行
./scripts/test-integration.sh
```

## API エンドポイント

### ヘルスチェック

```bash
# 基本的なヘルスチェック
GET /health

# Kubernetes接続を含む準備状態確認
GET /ready
```

### Deployment操作

```bash
# Scale to Zero
POST /api/v1/deployments/{namespace}/{name}/scale-to-zero
Content-Type: application/json
Authorization: Bearer <api-key>

{
  "reason": "コスト削減のため",
  "scheduled_scale_up": "2024-01-15T09:00:00Z"  # オプション
}

# Scale Up
POST /api/v1/deployments/{namespace}/{name}/scale-up
Content-Type: application/json
Authorization: Bearer <api-key>

{
  "replicas": 2,
  "reason": "業務開始のため"
}

# ステータス確認
GET /api/v1/deployments/{namespace}/{name}/status
Authorization: Bearer <api-key>
```

## 環境変数

| 変数名 | 説明 | デフォルト値 |
|--------|------|--------------|
| PORT | APIサーバーのポート | 8080 |
| LOG_LEVEL | ログレベル (debug, info, warn, error) | info |
| API_KEY | API認証キー（未設定の場合は認証無効） | - |
| GIN_MODE | Ginフレームワークのモード (debug, release, test) | release |
| KUBECONFIG | Kubernetesの設定ファイルパス | ~/.kube/config |

## ディレクトリ構造

```
.
├── main.go              # エントリーポイント
├── config/              # 設定管理
├── handlers/            # APIハンドラー
├── k8s/                 # Kubernetesクライアント
├── middleware/          # ミドルウェア（認証、ログ）
├── models/              # データモデル
├── utils/               # ユーティリティ関数
├── scripts/             # テスト・デプロイスクリプト
├── Makefile            # ビルド・テストタスク
└── README.md           # このファイル
```

## 開発

### 必要なツール

- Go 1.24以上
- make
- Docker（コンテナビルド用）
- kubectl（Kubernetes操作用）

### コード品質

```bash
# コードフォーマット
make fmt

# 静的解析
make vet

# リンター（要golangci-lint）
make lint
```

## トラブルシューティング

### Kubernetes接続エラー

`/ready`エンドポイントが`503`を返す場合：

1. kubeconfigが正しく設定されているか確認
2. クラスター内で実行する場合は、適切なRBACが設定されているか確認
3. ServiceAccountに必要な権限があるか確認

### 認証エラー

`401 Unauthorized`が返される場合：

1. `API_KEY`環境変数が設定されているか確認
2. リクエストヘッダーに`Authorization: Bearer <api-key>`が含まれているか確認
3. APIキーが正しいか確認

## ライセンス

このプロジェクトはサンプル実装です。