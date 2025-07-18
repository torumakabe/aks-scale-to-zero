# Operations Guide - AKS Scale to Zero

## 概要

このガイドは、AKS Scale to Zero システムの運用・監視・保守について説明します。

## システム構成

### コンポーネント

1. **AKS クラスタ**
   - システムノードプール（Scale API用）
   - ユーザーノードプール（Project A/B用、Scale to Zero対応）

2. **Scale API**
   - Namespace: `scale-system`
   - Deployment: `scale-api`
   - Service: `scale-api` (ClusterIP)
   - Replicas: 2

3. **サンプルアプリケーション**
   - Project A: `project-a` namespace
   - Project B: `project-b` namespace

### アクセス方法

```bash
# kubectl経由でのアクセス
kubectl port-forward -n scale-system svc/scale-api 8080:80

# クラスタ内からのアクセス
curl http://scale-api.scale-system.svc.cluster.local/health
```

## 監視

### ヘルスチェック

#### API サーバーの基本動作確認
```bash
# 基本的な動作確認
curl http://localhost:8080/health
# Expected: {"status":"healthy","time":"..."}

# Kubernetes接続確認
curl http://localhost:8080/ready
# Expected: {"status":"ready","kubernetes":"connected","time":"..."}
```

#### Pod状態の確認
```bash
# Scale API Pods確認
kubectl get pods -n scale-system -l app.kubernetes.io/name=scale-api

# Pod詳細確認
kubectl describe pod -n scale-system -l app.kubernetes.io/name=scale-api

# ログ確認
kubectl logs -n scale-system deployment/scale-api -f
```

### ノードプール監視

```bash
# ノード状態確認
kubectl get nodes --show-labels

# Project A/B ノード確認
kubectl get nodes -l project=a
kubectl get nodes -l project=b

# ノードプール自動スケール状態
az aks nodepool show --cluster-name <cluster-name> --name <nodepool-name> \
  --resource-group <resource-group> --query 'enableAutoScaling'
```

### メトリクス監視

#### Kubernetesメトリクス
```bash
# Deployment状態
kubectl get deployments -A

# Pod リソース使用状況
kubectl top pods -n scale-system
kubectl top nodes

# HPA状態（設定されている場合）
kubectl get hpa -A
```

#### Azure Monitor
- Log Analytics Workspaceにてコンテナインサイトを確認
- メトリクスアラートの設定・監視
- ノードプールのスケール動作の追跡

### ログ監視

#### アプリケーションログ
```bash
# Scale API ログ（JSON構造化ログ）
kubectl logs -n scale-system deployment/scale-api -f | jq '.'

# エラーログのフィルタリング
kubectl logs -n scale-system deployment/scale-api | grep '"level":"error"'

# 特定のリクエストのトレース
kubectl logs -n scale-system deployment/scale-api | grep 'scale-to-zero'
```

#### システムログ
```bash
# ノードのシステムログ
kubectl logs -n kube-system daemonset/azure-cni-networkmonitor

# Kubernetes APIサーバーログ（マネージドサービスのため限定的）
az aks get-credentials --resource-group <rg> --name <cluster>
kubectl get events --sort-by=.metadata.creationTimestamp
```

## アラートとトラブルシューティング

### 一般的な問題

#### 1. Scale API が応答しない

**症状:**
```bash
curl http://localhost:8080/health
# Error: Connection refused
```

**診断手順:**
```bash
# Pod状態確認
kubectl get pods -n scale-system
kubectl describe pod -n scale-system <pod-name>

# サービス確認
kubectl get svc -n scale-system scale-api
kubectl describe svc -n scale-system scale-api

# エンドポイント確認
kubectl get endpoints -n scale-system scale-api
```

**解決方法:**
```bash
# Pod再起動
kubectl rollout restart deployment/scale-api -n scale-system

# ログで原因調査
kubectl logs -n scale-system deployment/scale-api --previous
```

#### 2. Kubernetes API接続エラー

**症状:**
```bash
curl http://localhost:8080/ready
# {"status":"not ready","error":"unable to connect to Kubernetes API"}
```

**診断手順:**
```bash
# RBAC権限確認
kubectl auth can-i --list --as=system:serviceaccount:scale-system:scale-api-sa

# ServiceAccount確認
kubectl get sa -n scale-system scale-api-sa -o yaml

# ClusterRole確認
kubectl get clusterrole scale-api-role -o yaml
kubectl get clusterrolebinding scale-api-binding -o yaml
```

**解決方法:**
```bash
# RBAC再適用
kubectl apply -f /path/to/rbac.yaml

# ServiceAccount再作成
kubectl delete sa scale-api-sa -n scale-system
kubectl apply -f /path/to/serviceaccount.yaml
```

#### 3. Deployment が見つからない

**症状:**
```bash
curl -X POST http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-to-zero
# {"status":"error","message":"Deployment project-a/sample-app-a not found"}
```

**診断手順:**
```bash
# Deployment存在確認
kubectl get deployments -n project-a

# Namespace確認
kubectl get namespaces | grep project

# サンプルアプリの状態確認
kubectl get pods -n project-a
```

**解決方法:**
```bash
# サンプルアプリ再デプロイ
kubectl apply -f /path/to/sample-app-manifests/
```

#### 4. ノードプールがスケールしない

**症状:**
- Podが `Pending` 状態のまま
- ノード数が増加しない

**診断手順:**
```bash
# Pod状態とイベント確認
kubectl describe pod <pending-pod-name> -n <namespace>

# ノードプール設定確認
az aks nodepool show --cluster-name <cluster-name> --name <nodepool-name> \
  --resource-group <resource-group>

# Cluster Autoscaler ログ
kubectl logs -n kube-system deployment/cluster-autoscaler
```

**解決方法:**
```bash
# ノードプール手動スケール（一時的）
az aks nodepool scale --cluster-name <cluster-name> --name <nodepool-name> \
  --resource-group <resource-group> --node-count 1

# Cluster Autoscaler設定確認・再起動
kubectl rollout restart deployment/cluster-autoscaler -n kube-system
```

### パフォーマンス監視

#### API レスポンス時間
```bash
# レスポンス時間測定
time curl -s http://localhost:8080/api/v1/deployments/project-a/sample-app-a/status

# ログからレスポンス時間確認
kubectl logs -n scale-system deployment/scale-api | jq '.latency'
```

#### スケール操作時間
```bash
# スケール操作からPod起動までの時間測定
start_time=$(date +%s)
curl -X POST -d '{"replicas":1,"reason":"test"}' \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-up

# Pod Running待機
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=sample-app-a \
  -n project-a --timeout=300s

end_time=$(date +%s)
echo "Scale time: $((end_time - start_time)) seconds"
```

## 保守・メンテナンス

### 定期メンテナンス

#### 1. API サーバーの更新
```bash
# 新しいイメージでの更新
kubectl set image deployment/scale-api scale-api=<new-image> -n scale-system

# ローリングアップデート確認
kubectl rollout status deployment/scale-api -n scale-system

# 必要に応じてロールバック
kubectl rollout undo deployment/scale-api -n scale-system
```

#### 2. 設定の更新
```bash
# ConfigMap更新（ある場合）
kubectl apply -f updated-configmap.yaml

# 環境変数更新（Deployment再起動が必要）
kubectl patch deployment scale-api -n scale-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"scale-api","env":[{"name":"LOG_LEVEL","value":"debug"}]}]}}}}'

kubectl rollout restart deployment/scale-api -n scale-system
```

#### 3. ログローテーション
```bash
# Kubernetes自動ログローテーション確認
kubectl get node <node-name> -o yaml | grep logMaxSize

# 手動ログクリア（必要な場合）
kubectl delete pod -n scale-system -l app.kubernetes.io/name=scale-api
```

### バックアップ・復旧

#### マニフェストバックアップ
```bash
# 現在の設定をバックアップ
kubectl get all -n scale-system -o yaml > scale-system-backup.yaml
kubectl get all -n project-a -o yaml > project-a-backup.yaml
kubectl get all -n project-b -o yaml > project-b-backup.yaml

# RBAC設定バックアップ
kubectl get clusterrole scale-api-role -o yaml > rbac-backup.yaml
kubectl get clusterrolebinding scale-api-binding -o yaml >> rbac-backup.yaml
kubectl get sa scale-api-sa -n scale-system -o yaml >> rbac-backup.yaml
```

#### 復旧手順
```bash
# 1. Namespace作成
kubectl create namespace scale-system
kubectl create namespace project-a
kubectl create namespace project-b

# 2. RBAC復旧
kubectl apply -f rbac-backup.yaml

# 3. Scale API復旧
kubectl apply -f scale-system-backup.yaml

# 4. サンプルアプリ復旧
kubectl apply -f project-a-backup.yaml
kubectl apply -f project-b-backup.yaml

# 5. 動作確認
kubectl get pods -A
curl http://localhost:8080/health
```

## セキュリティ

### APIキー管理
```bash
# APIキー設定確認
kubectl get deployment scale-api -n scale-system -o yaml | grep API_KEY

# APIキー更新
kubectl patch deployment scale-api -n scale-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"scale-api","env":[{"name":"API_KEY","value":"new-api-key"}]}]}}}}'
```

### ネットワークセキュリティ
```bash
# NetworkPolicy確認（設定されている場合）
kubectl get networkpolicy -A

# Service mesh設定確認（使用している場合）
istioctl proxy-status
```

### RBAC監査
```bash
# 現在の権限確認
kubectl auth can-i --list --as=system:serviceaccount:scale-system:scale-api-sa

# 過剰な権限がないかチェック
kubectl describe clusterrole scale-api-role
```

## 容量計画

### リソース使用量監視
```bash
# Scale API リソース使用量
kubectl top pod -n scale-system --containers

# ノードリソース使用量
kubectl top nodes

# 推奨リソースリクエスト/リミット確認
kubectl describe deployment scale-api -n scale-system | grep -A 10 "Requests\|Limits"
```

### スケール計画
```bash
# 過去のスケール履歴分析
kubectl logs -n scale-system deployment/scale-api --since=24h | \
  grep '"path":"/api/v1/deployments/' | jq '.path, .timestamp'

# ノードプール使用率分析
kubectl get nodes -o custom-columns="NAME:.metadata.name,PROJECT:.metadata.labels.project,PODS:.status.allocatable.pods"
```

## 災害復旧

### インフラストラクチャ障害対応
1. Azure リソースグループ全体の復旧: `azd up`
2. AKS クラスタ個別復旧: Bicep テンプレート再実行
3. アプリケーション復旧: マニフェスト再適用

### データ損失対応
1. Kubernetes設定は宣言的に管理されているため、マニフェストから復旧可能
2. ステートフルなデータは存在しない（Scale APIはステートレス）
3. ログデータはLog Analytics Workspaceに保持

## 運用チェックリスト

### 日次チェック
- [ ] Scale API ヘルスチェック実行
- [ ] ノードプール状態確認
- [ ] エラーログ確認
- [ ] リソース使用量確認

### 週次チェック
- [ ] API レスポンス時間分析
- [ ] スケール操作履歴レビュー
- [ ] セキュリティログ確認
- [ ] バックアップ検証

### 月次チェック
- [ ] 容量計画見直し
- [ ] RBAC権限監査
- [ ] 災害復旧手順テスト
- [ ] ドキュメント更新

## 連絡先・エスカレーション

- **Level 1**: 基本的な監視アラート、自動復旧
- **Level 2**: 手動介入が必要な問題、設定変更
- **Level 3**: アーキテクチャ変更、重大な障害対応

参考資料:
- [API Reference](./api-reference.md)
- [トラブルシューティングガイド](./troubleshooting.md)
- [実装プラン](./plan.md)
