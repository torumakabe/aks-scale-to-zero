# Integration Tests

AKS Scale to Zero プロジェクトの統合テストスイートです。実際のAKSクラスタ環境でScale APIの動作を検証します。

## 前提条件

### 必須環境
- **kubectl**: AKSクラスタに接続設定済み
- **jq**: JSON レスポンス解析用
- **curl**: HTTP API テスト用
- **go**: ユニットテスト実行用（1.24+）

### デプロイ済みリソース
- AKSクラスタ（azd upで構築済み）
- scale-api サービス（scale-system namespace）
- sample-app-a（project-a namespace）
- sample-app-b（project-b namespace）
- triton-inference-server（project-b namespace、GPUテスト用）

## テスト実行方法

### 推奨実行方法（個別テスト）

時間のかかる処理があるため、必要なテストを個別に実行することを推奨します。

```bash
# 事前準備：ユニットテスト品質確認
cd tests/unit
make ci   # lint + vet + test + coverage

# 統合テスト実行（個別）
cd ../integration

# 推奨実行順序:
# 1. Scale API基本機能テスト（12テスト）
./test-scale-api.sh

# 2. ステータス取得テスト（13テスト）
./test-get-status.sh

# 3. Scale to Zeroノードテスト（8テスト） ※20-30分程度
# 注意: ノードのプロビジョニングとスケールダウン監視のため長時間実行されます
./test-scale-to-zero.sh

# 4. GPU Triton推論テスト（12テスト） ※GPU対応クラスタのみ、15-20分程度
# 注意: GPUノードプールが必要です。存在しない場合はスキップされます
./test-triton-inference.sh
```

## テスト内容

### test-scale-api.sh（12テスト）
- **Health Check**: health/ready エンドポイント確認
- **Deployment Status**: 現在のデプロイメント状態取得
- **Scale Up to 3**: 3レプリカへのスケールアップ実行
- **Scale Up Verification**: APIステータスでの確認
- **Actual Replica Count**: 実際のレプリカ数確認
- **Scale Down to 2**: 2レプリカへのスケールダウン実行
- **Scale Down Verification**: スケールダウン結果確認
- **Scale to Zero**: ゼロスケール実行
- **Zero Scale Verification**: ゼロスケール結果確認
- **Recovery from Zero**: ゼロから1レプリカへの復帰
- **Recovery Verification**: 復帰結果確認
- **Response Validation**: JSON構造とHTTPステータス確認

### test-scale-to-zero.sh（8テスト）
**実行時間**: 約20-30分（ノードプロビジョニングとスケールダウン監視含む）
- **Deployment Check**: デプロイメントの存在確認
- **Scale Up for Node Provisioning**: ノードプロビジョニングのための1レプリカへのスケールアップ
- **Wait for Deployment Ready**: デプロイメント準備完了待機（最大15分）
- **Verify Project Nodes**: プロジェクト用ノードの存在確認
- **Scale to Zero**: ゼロスケール実行
- **Verify All Pods Terminated**: 全Pod終了確認
- **Monitor Node Scale Down**: ノードスケールダウン監視（最大20分、60秒ごと）
- **Final Node Count Verification**: 最終的にノード数がゼロになったことの確認

### test-get-status.sh（13テスト）
- **Health Endpoints**: health/ready エンドポイント
- **Basic Status Functionality**: 基本的なステータスエンドポイント機能
- **Response Structure Validation**: 
  - deployment.name フィールド
  - deployment.namespace フィールド
  - deployment オブジェクト
  - deployment.desired_replicas フィールド
  - deployment.current_replicas フィールド
- **Numeric Replica Validation**: レプリカ数の数値検証
- **Error Handling**:
  - 存在しないデプロイメント（404）
  - 存在しないnamespace（404）
- **Performance Test**: レスポンス時間測定（2秒以内）
- **Stability Test**: 5回連続リクエストの安定性
- **JSON Format Validation**: JSONフォーマット検証

### test-triton-inference.sh（12テスト）
**前提条件**: GPU対応のAKSクラスター（GPUノードプールが必要）
**実行時間**: 約15-20分（GPUノードプロビジョニング含む）
- **GPU Node Pool Check**: GPUノードプールの可用性確認
- **Current Deployment State**: デプロイメントの現在の状態確認
- **Scale API Port Forward**: Scale APIへのポートフォワード設定
- **GPU Deployment Scale Up**: GPU deploymentのスケールアップ（必要時のみ）
- **Wait for GPU Deployment**: デプロイメント準備完了待機（最大15分）
- **GPU Pod Running**: GPUポッドの実行状態確認
- **Triton Port Forward**: Triton Serverへのポートフォワード設定
- **Triton Server Ready**: Triton Server準備完了待機（最大3分、10秒ごと再試行）
- **Triton Health Check**: Triton Serverヘルスエンドポイント確認
- **ResNet50 Model Ready**: ResNet50モデルのロード確認
- **ResNet50 Inference Test**: 実際の推論実行テスト（Pythonによる）
  - 正しいデータサイズ生成（1x3x224x224）
  - 推論結果の形状検証（1x1000クラス）
- **Cleanup**: ポートフォワードクリーンアップ

## テスト結果の読み方

### 成功例
```
✓ PASS: Health Endpoint
✓ PASS: Scale Deployment Up
✓ PASS: Verify Scale Up Response

=== Test Summary ===
Tests Passed: 12
Tests Failed: 0
🎉 All Scale API tests passed!
```

### 失敗例
```
✗ FAIL: Scale Deployment Up
  Expected status: success, Got: error

=== Test Summary ===
Tests Passed: 11
Tests Failed: 1
❌ Some Scale API tests failed
```

## トラブルシューティング

### よくある問題

#### 1. kubectl接続エラー
```
❌ kubectl is not configured or cluster is not accessible
```
**解決方法:**
```bash
az aks get-credentials --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_CLUSTER_NAME
kubectl cluster-info
```

#### 2. Port-forward接続失敗
```
Failed to establish port-forward connection
```
**解決方法:**
```bash
# Scale APIのPod状態確認
kubectl get pods -n scale-system
kubectl logs -n scale-system deployment/scale-api

# サービス確認
kubectl get svc -n scale-system
```

#### 3. Scale API応答エラー
```
✗ FAIL: Scale Deployment Up
```
**解決方法:**
```bash
# RBAC権限確認
kubectl auth can-i --list --as=system:serviceaccount:scale-system:scale-api-sa

# APIログ確認
kubectl logs -n scale-system deployment/scale-api -f
```

#### 4. サンプルアプリが見つからない
```
deployment.apps "sample-app-a" not found
```
**解決方法:**
```bash
# デプロイメント確認
kubectl get deployments -n project-a
kubectl get deployments -n project-b

# 必要に応じて再デプロイ
kubectl apply -f ../../src/samples/app-a/manifests/
kubectl apply -f ../../src/samples/app-b/manifests/
```

## 開発者向け情報

### テストフレームワーク

各テストスクリプトは共通の構造を持ちます：

```bash
# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# テスト実行関数
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "\n${BLUE}Testing: ${test_name}${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✓ PASS: ${test_name}${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL: ${test_name}${NC}"
        ((TESTS_FAILED++))
    fi
}

# JSON検証関数
check_json_response() {
    local response="$1"
    local expected_field="$2"
    
    if echo "$response" | jq -e ".${expected_field}" >/dev/null 2>&1; then
        return 0
    else
        echo -e "${RED}Missing expected field: ${expected_field}${NC}"
        return 1
    fi
}
```

### 新しいテストの追加

1. 既存スクリプトに追加する場合：
```bash
run_test "New Test Description" \
    'YOUR_TEST_COMMAND_HERE'
```

2. 新しいテストスクリプトを作成する場合：
   - 既存スクリプトをベースにコピー
   - `NAMESPACE`、`DEPLOYMENT`を適切に設定
   - `run-integration-tests.sh`に追加

### 継続的改善

- テスト実行時間の最適化
- より詳細なエラーメッセージ
- テスト結果のJUnit XML形式出力
- 並列テスト実行の検討

## 参考資料

- [実装プラン](../../docs/plan.md) - Step 17詳細
- [API仕様](../../src/api/README.md) - Scale API詳細
- [ユニットテスト](../unit/README.md) - 事前品質確認
