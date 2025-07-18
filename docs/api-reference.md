# Scale API Reference

AKS Scale to Zero プロジェクトのScale API仕様書です。このAPIは、Kubernetes Deploymentのスケールアップ・スケールダウン制御を提供します。

## Base URL

```
http://localhost:8080  # ローカル開発時
http://<scale-api-service>/  # Kubernetes クラスタ内
```

## 認証

APIキーによるBearer Token認証を使用します（オプション）。

```http
Authorization: Bearer <your-api-key>
```

環境変数 `API_KEY` が設定されている場合、すべてのAPI操作エンドポイント（`/api/v1/*`）で認証が必要になります。ヘルスチェック系エンドポイント（`/health`, `/ready`）は認証不要です。

## Content Type

すべてのリクエストとレスポンスは JSON 形式です。

```http
Content-Type: application/json
```

## Error Handling

エラーレスポンスは統一された形式で返されます：

```json
{
  "status": "error",
  "message": "エラーの説明",
  "error": "詳細なエラー情報",
  "timestamp": "2025-07-17T10:00:00Z"
}
```

### HTTP ステータスコード

- `200` - 成功
- `400` - 不正なリクエスト（JSONフォーマットエラー、バリデーションエラー）
- `401` - 認証エラー（APIキーが無効または未指定）
- `404` - リソースが見つからない（Deployment、Namespace）
- `500` - サーバー内部エラー（Kubernetes API エラー）
- `503` - サービス利用不可（Kubernetes 接続エラー）

## エンドポイント

### Health Check Endpoints

#### GET /health

基本的なAPIサーバーの動作確認を行います。認証不要。

**レスポンス:**
```json
{
  "status": "healthy",
  "time": "2025-07-17T10:00:00Z"
}
```

**HTTPステータス:** `200`

#### GET /ready

Kubernetes API への接続を含む、APIサーバーの準備状態を確認します。認証不要。

**成功レスポンス:**
```json
{
  "status": "ready",
  "kubernetes": "connected",
  "time": "2025-07-17T10:00:00Z"
}
```

**エラーレスポンス:**
```json
{
  "status": "not ready",
  "error": "unable to connect to Kubernetes API",
  "time": "2025-07-17T10:00:00Z"
}
```

**HTTPステータス:** `200` (ready) / `503` (not ready)

### Deployment Management Endpoints

#### POST /api/v1/deployments/{namespace}/{name}/scale-to-zero

指定されたDeploymentをレプリカ数0にスケールダウンします。

**パラメータ:**
- `namespace` (path, required): Kubernetesネームスペース名
- `name` (path, required): Deployment名

**リクエストボディ:**
```json
{
  "reason": "コスト削減のため",
  "scheduled_scale_up": "2025-07-18T09:00:00Z"
}
```

**フィールド:**
- `reason` (string, required): スケールダウンの理由 (1-500文字)
- `scheduled_scale_up` (string, optional): 予定されたスケールアップ時刻 (ISO 8601形式)

**成功レスポンス:**
```json
{
  "status": "success",
  "message": "Deployment scaled to zero",
  "deployment": {
    "name": "sample-app-a",
    "namespace": "project-a",
    "previous_replicas": 2,
    "current_replicas": 0,
    "target_replicas": 0,
    "target_status": "scaled-to-zero",
    "scaling_reason": "コスト削減のため",
    "scheduled_scale_up": "2025-07-18T09:00:00Z"
  },
  "timestamp": "2025-07-17T10:00:00Z"
}
```

**HTTPステータス:** `200` (成功) / `400` (不正リクエスト) / `404` (Deployment未発見) / `500` (内部エラー)

#### POST /api/v1/deployments/{namespace}/{name}/scale-up

指定されたDeploymentを指定したレプリカ数にスケールアップします。

**パラメータ:**
- `namespace` (path, required): Kubernetesネームスペース名
- `name` (path, required): Deployment名

**リクエストボディ:**
```json
{
  "replicas": 2,
  "reason": "業務開始のため"
}
```

**フィールド:**
- `replicas` (integer, required): 目標レプリカ数 (1以上)
- `reason` (string, required): スケールアップの理由 (1-500文字)

**成功レスポンス:**
```json
{
  "status": "success",
  "message": "Deployment scaled to 2 replicas",
  "deployment": {
    "name": "sample-app-a",
    "namespace": "project-a",
    "previous_replicas": 0,
    "current_replicas": 0,
    "target_replicas": 2,
    "target_status": "scaling-up",
    "scaling_reason": "業務開始のため"
  },
  "timestamp": "2025-07-17T10:00:00Z"
}
```

**HTTPステータス:** `200` (成功) / `400` (不正リクエスト) / `404` (Deployment未発見) / `500` (内部エラー)

#### GET /api/v1/deployments/{namespace}/{name}/status

指定されたDeploymentの現在の状態を取得します。

**パラメータ:**
- `namespace` (path, required): Kubernetesネームスペース名
- `name` (path, required): Deployment名

**成功レスポンス:**
```json
{
  "status": "success",
  "message": "Deployment status retrieved successfully",
  "deployment": {
    "name": "sample-app-a",
    "namespace": "project-a",
    "deployment": "sample-app-a",
    "current_replicas": 2,
    "desired_replicas": 2,
    "available_replicas": 2,
    "status": "active",
    "last_scale_time": "2025-07-17T09:30:00Z"
  },
  "timestamp": "2025-07-17T10:00:00Z"
}
```

**Deployment Status値:**
- `active` - アクティブ（desired_replicas > 0）
- `inactive` - 非アクティブ（desired_replicas = 0）
- `scaling` - スケール中（current_replicas ≠ desired_replicas）
- `unknown` - 不明

**HTTPステータス:** `200` (成功) / `404` (Deployment未発見) / `500` (内部エラー)

## データモデル

### ScaleRequest

```json
{
  "reason": "string (1-500文字, required)",
  "scheduled_scale_up": "string (ISO 8601, optional)"
}
```

### ScaleUpRequest

```json
{
  "replicas": "integer (≥1, required)",
  "reason": "string (1-500文字, required)"
}
```

### ScaleResponse

```json
{
  "status": "string (success/error)",
  "message": "string",
  "deployment": "DeploymentInfo (optional)",
  "error": "string (optional)",
  "timestamp": "string (ISO 8601)"
}
```

### DeploymentInfo

```json
{
  "name": "string",
  "namespace": "string",
  "previous_replicas": "integer",
  "current_replicas": "integer",
  "target_replicas": "integer",
  "target_status": "string",
  "scaling_reason": "string (optional)",
  "scheduled_scale_up": "string (ISO 8601, optional)"
}
```

### DeploymentStatusResponse

```json
{
  "status": "string (success/error)",
  "message": "string",
  "deployment": "DeploymentStatus (optional)",
  "error": "string (optional)",
  "timestamp": "string (ISO 8601)"
}
```

### DeploymentStatus

```json
{
  "name": "string",
  "namespace": "string",
  "deployment": "string",
  "current_replicas": "integer",
  "desired_replicas": "integer",
  "available_replicas": "integer",
  "status": "string (active/inactive/scaling/unknown)",
  "last_scale_time": "string (ISO 8601)"
}
```

## 使用例

### 1. Scale to Zero ワークフロー

```bash
# 1. 現在の状態確認
curl -H "Authorization: Bearer <api-key>" \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/status

# 2. Scale to Zero実行
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <api-key>" \
  -d '{"reason": "夜間のコスト削減"}' \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-to-zero

# 3. 結果確認
curl -H "Authorization: Bearer <api-key>" \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/status
```

### 2. スケールアップ ワークフロー

```bash
# 1. スケールアップ実行
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <api-key>" \
  -d '{"replicas": 3, "reason": "朝の業務開始"}' \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-up

# 2. スケール完了まで監視
while true; do
  curl -s -H "Authorization: Bearer <api-key>" \
    http://localhost:8080/api/v1/deployments/project-a/sample-app-a/status | \
    jq '.deployment.status'
  sleep 5
done
```

### 3. ヘルスチェック

```bash
# API サーバー動作確認
curl http://localhost:8080/health

# Kubernetes 接続確認
curl http://localhost:8080/ready
```

## Rate Limiting

現在のバージョンではRate Limitingは実装されていませんが、将来のバージョンで追加予定です。

## Logging

すべてのAPI リクエストは構造化ログとして記録されます：

```json
{
  "time": "2025-07-17T10:00:00Z",
  "level": "info",
  "method": "POST",
  "path": "/api/v1/deployments/project-a/sample-app-a/scale-to-zero",
  "status": 200,
  "latency": "45ms",
  "user_agent": "curl/7.68.0"
}
```

## WebSocket Support

現在のバージョンではWebSocketは対応していませんが、リアルタイムステータス更新機能として将来のバージョンで検討中です。

## SDK & Client Libraries

現在、公式SDKは提供していませんが、標準的なHTTP クライアントライブラリを使用してAPIを呼び出すことができます。

### Go例:

```go
import (
    "bytes"
    "encoding/json"
    "net/http"
)

type ScaleRequest struct {
    Reason string `json:"reason"`
}

func scaleToZero(namespace, deployment, reason string) error {
    req := ScaleRequest{Reason: reason}
    body, _ := json.Marshal(req)
    
    resp, err := http.Post(
        fmt.Sprintf("http://localhost:8080/api/v1/deployments/%s/%s/scale-to-zero", 
                   namespace, deployment),
        "application/json",
        bytes.NewBuffer(body),
    )
    if err != nil {
        return err
    }
    defer resp.Body.Close()
    
    return nil
}
```

### curl例:

```bash
#!/bin/bash
API_KEY="your-api-key"
BASE_URL="http://localhost:8080"

scale_to_zero() {
    local namespace=$1
    local deployment=$2
    local reason=$3
    
    curl -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        -d "{\"reason\": \"$reason\"}" \
        "$BASE_URL/api/v1/deployments/$namespace/$deployment/scale-to-zero"
}

scale_to_zero "project-a" "sample-app-a" "夜間コスト削減"
```

## Changelog

### v1.0.0 (2025-07-17)
- 初回リリース
- Scale to Zero、Scale Up、Status確認機能
- APIキー認証対応
- ヘルスチェックエンドポイント

## Support

- **Issues**: [GitHub Issues](https://github.com/torumakabe/aks-scale-to-zero/issues)
- **Documentation**: [プロジェクトドキュメント](../../docs/)
- **実装プラン**: [Step 20完了済み](../../docs/plan.md#step-20-apiドキュメント作成)
