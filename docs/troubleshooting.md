# Troubleshooting Guide - AKS Scale to Zero

## 概要

このガイドでは、AKS Scale to Zero システムでよく発生する問題の診断と解決方法を説明します。

## 問題分類

### 🔴 Critical (緊急)
- Scale API が完全に応答しない
- Kubernetes クラスタ全体の障害
- セキュリティ侵害の疑い

### 🟡 Warning (警告)
- Scale API の一部機能が動作しない
- レスポンス時間の大幅な増加
- ノードプールの自動スケールが動作しない

### 🟢 Info (情報)
- 単発的なエラー
- パフォーマンスの軽微な劣化
- 設定変更に関する質問

## 診断フローチャート

```
問題発生
    ↓
Scale API応答確認
    ↓
┌─────── OK ──────┐          ┌─── NG ────┐
│                 │          │           │
│ 機能別診断      │          │ Pod状態    │
│ - Scale to Zero │          │ 確認      │
│ - Scale Up      │          │           │
│ - Status取得    │          └───────────┘
│                 │
└─────────────────┘
```

## 共通診断コマンド

### 基本ヘルスチェック
```bash
# 1. Scale API 基本動作確認
curl -s http://localhost:8080/health | jq '.'

# 2. Kubernetes接続確認
curl -s http://localhost:8080/ready | jq '.'

# 3. Pod状態確認
kubectl get pods -n scale-system -o wide

# 4. Service状態確認
kubectl get svc -n scale-system

# 5. ログ確認
kubectl logs -n scale-system deployment/scale-api --tail=50
```

### システム情報収集
```bash
# Kubernetes バージョン
kubectl version --short

# ノード状態
kubectl get nodes -o wide

# リソース使用量
kubectl top nodes
kubectl top pods -n scale-system

# イベント履歴
kubectl get events --sort-by=.metadata.creationTimestamp --all-namespaces | tail -20
```

## 問題別解決ガイド

### 1. Scale API 応答問題

#### 問題: API が完全に応答しない
```bash
curl http://localhost:8080/health
# Error: Connection refused
```

**診断手順:**
```bash
# Step 1: Port-forward状態確認
ps aux | grep port-forward
kubectl port-forward -n scale-system svc/scale-api 8080:80 &

# Step 2: Pod状態確認
kubectl describe pods -n scale-system -l app.kubernetes.io/name=scale-api

# Step 3: Service確認
kubectl get svc -n scale-system scale-api -o yaml

# Step 4: エンドポイント確認
kubectl get endpoints -n scale-system scale-api
```

**解決方法:**
```bash
# 方法1: Pod再起動
kubectl rollout restart deployment/scale-api -n scale-system
kubectl rollout status deployment/scale-api -n scale-system

# 方法2: Service再作成（必要な場合）
kubectl delete svc scale-api -n scale-system
kubectl apply -f src/api/manifests/service.yaml

# 方法3: 完全再デプロイ
kubectl delete -f src/api/manifests/
kubectl apply -f src/api/manifests/
```

#### 問題: /ready エンドポイントが 503 を返す
```bash
curl http://localhost:8080/ready
# {"status":"not ready","error":"unable to connect to Kubernetes API"}
```

**診断手順:**
```bash
# RBAC権限確認
kubectl auth can-i get deployments --as=system:serviceaccount:scale-system:scale-api-sa
kubectl auth can-i list deployments --as=system:serviceaccount:scale-system:scale-api-sa
kubectl auth can-i update deployments --as=system:serviceaccount:scale-system:scale-api-sa

# ServiceAccount設定確認
kubectl get sa scale-api-sa -n scale-system -o yaml

# ClusterRoleBinding確認
kubectl get clusterrolebinding scale-api-binding -o yaml
```

**解決方法:**
```bash
# RBAC再適用
kubectl apply -f src/api/manifests/rbac.yaml

# ServiceAccount再作成
kubectl delete sa scale-api-sa -n scale-system
kubectl apply -f src/api/manifests/serviceaccount.yaml

# Pod再起動（新しい権限を適用）
kubectl rollout restart deployment/scale-api -n scale-system
```

### 2. Scale 操作問題

#### 問題: Scale to Zero が失敗する
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"reason": "test"}' \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-to-zero
# {"status":"error","message":"Failed to scale deployment"}
```

**診断手順:**
```bash
# Step 1: Deployment存在確認
kubectl get deployment sample-app-a -n project-a

# Step 2: Scale API ログ確認
kubectl logs -n scale-system deployment/scale-api | grep scale-to-zero

# Step 3: Deployment詳細確認
kubectl describe deployment sample-app-a -n project-a

# Step 4: 手動スケール確認
kubectl scale deployment sample-app-a --replicas=0 -n project-a
```

**解決方法:**
```bash
# 方法1: Deployment再作成
kubectl delete deployment sample-app-a -n project-a
kubectl apply -f src/samples/app-a/manifests/deployment.yaml

# 方法2: 手動でレプリカ修復
kubectl patch deployment sample-app-a -n project-a \
  -p '{"spec":{"replicas":1}}'

# 方法3: API権限確認・修正
kubectl apply -f src/api/manifests/rbac.yaml
kubectl rollout restart deployment/scale-api -n scale-system
```

#### 問題: Scale Up 後にPodが起動しない
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"replicas": 2, "reason": "test"}' \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-up
# 成功するが、Podが Pending のまま
```

**診断手順:**
```bash
# Step 1: Pod状態とイベント確認
kubectl get pods -n project-a
kubectl describe pod <pod-name> -n project-a

# Step 2: ノード確認
kubectl get nodes --show-labels | grep project=a

# Step 3: Cluster Autoscaler確認
kubectl logs -n kube-system deployment/cluster-autoscaler

# Step 4: ノードプール設定確認
az aks nodepool show --cluster-name <cluster-name> --name project-a-pool \
  --resource-group <resource-group>
```

**解決方法:**
```bash
# 方法1: ノードプール手動スケール
az aks nodepool scale --cluster-name <cluster-name> --name project-a-pool \
  --resource-group <resource-group> --node-count 1

# 方法2: nodeSelector確認・修正
kubectl patch deployment sample-app-a -n project-a \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"project":"a"}}}}}'

# 方法3: Cluster Autoscaler再起動
kubectl rollout restart deployment/cluster-autoscaler -n kube-system
```

### 3. 認証・認可問題

#### 問題: 401 Unauthorized エラー
```bash
curl -X POST http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-to-zero
# {"status":"error","message":"Unauthorized"}
```

**診断手順:**
```bash
# API_KEY環境変数確認
kubectl get deployment scale-api -n scale-system -o yaml | grep -A 5 -B 5 API_KEY

# ログで認証エラー確認
kubectl logs -n scale-system deployment/scale-api | grep -i auth
```

**解決方法:**
```bash
# 方法1: 認証ヘッダー付きリクエスト
curl -H "Authorization: Bearer <api-key>" \
  -X POST -H "Content-Type: application/json" \
  -d '{"reason": "test"}' \
  http://localhost:8080/api/v1/deployments/project-a/sample-app-a/scale-to-zero

# 方法2: API_KEY無効化（開発・テスト用）
kubectl patch deployment scale-api -n scale-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"scale-api","env":[{"name":"API_KEY","value":""}]}]}}}}'

# 方法3: 新しいAPIキー設定
kubectl patch deployment scale-api -n scale-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"scale-api","env":[{"name":"API_KEY","value":"new-api-key"}]}]}}}}'
```

### 4. パフォーマンス問題

#### 問題: API レスポンスが遅い（>5秒）
```bash
time curl http://localhost:8080/api/v1/deployments/project-a/sample-app-a/status
# real 0m8.234s
```

**診断手順:**
```bash
# Step 1: API ログでレスポンス時間確認
kubectl logs -n scale-system deployment/scale-api | jq '.latency'

# Step 2: Pod リソース使用量確認
kubectl top pods -n scale-system

# Step 3: Kubernetes API応答時間確認
time kubectl get deployment sample-app-a -n project-a

# Step 4: 同時リクエスト数確認
kubectl logs -n scale-system deployment/scale-api | \
  grep "$(date +%Y-%m-%d)" | wc -l
```

**解決方法:**
```bash
# 方法1: Pod リソース制限緩和
kubectl patch deployment scale-api -n scale-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"scale-api","resources":{"requests":{"memory":"256Mi","cpu":"200m"},"limits":{"memory":"512Mi","cpu":"500m"}}}]}}}}'

# 方法2: レプリカ数増加
kubectl scale deployment scale-api --replicas=3 -n scale-system

# 方法3: ログレベル変更（Debugログを削減）
kubectl patch deployment scale-api -n scale-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"scale-api","env":[{"name":"LOG_LEVEL","value":"info"}]}]}}}}'
```

### 5. ネットワーク問題

#### 問題: Service Discovery が動作しない
```bash
kubectl exec -it <test-pod> -- nslookup scale-api.scale-system.svc.cluster.local
# NXDOMAIN
```

**診断手順:**
```bash
# DNS設定確認
kubectl get svc -n kube-system kube-dns
kubectl logs -n kube-system deployment/coredns

# Service設定確認
kubectl get svc -n scale-system scale-api -o yaml

# EndPoints確認
kubectl get endpoints -n scale-system scale-api
```

**解決方法:**
```bash
# 方法1: CoreDNS再起動
kubectl rollout restart deployment/coredns -n kube-system

# 方法2: Service再作成
kubectl delete svc scale-api -n scale-system
kubectl apply -f src/api/manifests/service.yaml

# 方法3: Pod selector確認
kubectl get pods -n scale-system --show-labels
kubectl get svc scale-api -n scale-system -o yaml | grep selector
```

## 高度なトラブルシューティング

### ログ分析

#### エラーパターン解析
```bash
# 1. JSON構造化ログからエラー抽出
kubectl logs -n scale-system deployment/scale-api --since=1h | \
  jq 'select(.level == "error")' | \
  jq -r '.message' | sort | uniq -c | sort -nr

# 2. API エンドポイント別エラー率
kubectl logs -n scale-system deployment/scale-api --since=1h | \
  jq -r 'select(.status >= 400) | "\(.status) \(.path)"' | \
  sort | uniq -c | sort -nr

# 3. レスポンス時間分析
kubectl logs -n scale-system deployment/scale-api --since=1h | \
  jq -r 'select(.latency) | .latency' | \
  sed 's/ms//' | awk '{sum+=$1; n++} END {print "Average:", sum/n "ms"}'
```

#### リアルタイム監視
```bash
# 1. リアルタイムログ監視
kubectl logs -n scale-system deployment/scale-api -f | \
  jq --unbuffered 'select(.level == "error" or .status >= 400)'

# 2. メトリクス監視（Prometheus利用可能な場合）
kubectl port-forward -n scale-system svc/scale-api 9090:9090 &
curl http://localhost:9090/metrics

# 3. イベント監視
kubectl get events --all-namespaces --watch
```

### パフォーマンス分析

#### ボトルネック特定
```bash
# 1. CPU/メモリプロファイリング
kubectl exec -it -n scale-system <scale-api-pod> -- \
  curl http://localhost:8080/debug/pprof/profile

# 2. Goroutine分析
kubectl exec -it -n scale-system <scale-api-pod> -- \
  curl http://localhost:8080/debug/pprof/goroutine

# 3. データベース接続分析（該当する場合）
kubectl logs -n scale-system deployment/scale-api | \
  grep -i "database\|connection\|timeout"
```

### セキュリティ監査

#### アクセスログ分析
```bash
# 1. 異常なアクセスパターン検出
kubectl logs -n scale-system deployment/scale-api --since=24h | \
  jq -r 'select(.status >= 400) | "\(.remote_ip) \(.user_agent) \(.path)"' | \
  sort | uniq -c | sort -nr | head -10

# 2. 認証失敗分析
kubectl logs -n scale-system deployment/scale-api --since=24h | \
  jq 'select(.status == 401)' | \
  jq -r '"\(.timestamp) \(.remote_ip) \(.path)"'

# 3. 権限昇格試行検出
kubectl logs -n scale-system deployment/scale-api --since=24h | \
  grep -i "forbidden\|unauthorized\|denied"
```

## 予防措置

### モニタリング設定
```bash
# 1. ヘルスチェック自動化
while true; do
  if ! curl -s http://localhost:8080/health > /dev/null; then
    echo "$(date): Scale API health check failed" | \
      tee -a /var/log/scale-api-monitor.log
  fi
  sleep 30
done

# 2. リソース監視
kubectl top pods -n scale-system --no-headers | \
  awk '{if($3 > 80) print "High CPU usage: "$1" "$3}'

# 3. ログローテーション確認
kubectl get pods -n scale-system -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'
```

### 自動復旧スクリプト
```bash
#!/bin/bash
# auto-recovery.sh
LOG_FILE="/var/log/scale-api-recovery.log"

log() {
    echo "$(date): $1" | tee -a $LOG_FILE
}

# ヘルスチェック
if ! curl -s --connect-timeout 5 http://localhost:8080/health > /dev/null; then
    log "Health check failed, attempting recovery"
    
    # Pod再起動
    kubectl rollout restart deployment/scale-api -n scale-system
    
    # 復旧確認（最大5分間）
    for i in {1..30}; do
        sleep 10
        if curl -s --connect-timeout 5 http://localhost:8080/health > /dev/null; then
            log "Recovery successful after ${i}0 seconds"
            exit 0
        fi
    done
    
    log "Recovery failed, manual intervention required"
    exit 1
fi
```

## エスカレーション基準

### Level 1 → Level 2
- 自動復旧スクリプトが3回連続で失敗
- API レスポンス時間が10秒を超過
- エラー率が50%を超過

### Level 2 → Level 3
- Kubernetes クラスタ全体に影響
- セキュリティインシデントの疑い
- データ整合性の問題

### インシデント報告テンプレート
```
件名: [AKS Scale to Zero] <重要度> - <問題の概要>

発生時刻: YYYY-MM-DD HH:MM:SS
検出方法: <監視/ユーザー報告/自動検出>
影響範囲: <影響を受けるコンポーネント/ユーザー>
症状: <観測される問題>
実施した診断: <実行したコマンド/確認項目>
一時的対応: <実施した応急処置>
根本原因: <判明している場合>
恒久対策: <予定している対策>
```

## 参考資料

- [Operations Guide](./operations-guide.md) - 基本的な運用手順
- [API Reference](./api-reference.md) - APIの詳細仕様
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug-application-cluster/) - 公式ドキュメント
- [Azure AKS Troubleshooting](https://docs.microsoft.com/en-us/azure/aks/troubleshooting) - Azure公式ガイド

---

**緊急時連絡先:** 
- レベル1: 自動化システム
- レベル2: システム管理者
- レベル3: アーキテクチャチーム
