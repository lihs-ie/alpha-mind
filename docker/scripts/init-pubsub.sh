#!/usr/bin/env bash
# init-pubsub.sh
# Pub/Sub エミュレータにトピックとサブスクリプションを作成する。
# INF-004 の命名規則に従い、Terraform pubsub/main.tf の event_subscribers と完全一致させる。
# 冪等: 既存リソースへの再作成はスキップされる（HTTP 409 は無視）。

set -euo pipefail

PUBSUB_HOST="${PUBSUB_EMULATOR_HOST:-localhost:8085}"
PROJECT_ID="${GCP_PROJECT_ID:-alpha-mind-local}"
BASE_URL="http://${PUBSUB_HOST}"

# サービスのDockerネットワーク内部ポート（各サービスはコンテナ内で8080をリッスン）
BFF_URL="http://bff:8080"
DATA_COLLECTOR_URL="http://data-collector:8080"
FEATURE_ENGINEERING_URL="http://feature-engineering:8080"
SIGNAL_GENERATOR_URL="http://signal-generator:8080"
PORTFOLIO_PLANNER_URL="http://portfolio-planner:8080"
RISK_GUARD_URL="http://risk-guard:8080"
EXECUTION_URL="http://execution:8080"
AUDIT_LOG_URL="http://audit-log:8080"
INSIGHT_COLLECTOR_URL="http://insight-collector:8080"
AGENT_ORCHESTRATOR_URL="http://agent-orchestrator:8080"
HYPOTHESIS_LAB_URL="http://hypothesis-lab:8080"

curl_status() {
  curl -sS --retry 10 --retry-delay 1 --retry-connrefused \
    -o /dev/null -w "%{http_code}" "$@" || echo "000"
}

# イベント配線: event_type_dash => "subscriber1 subscriber2 ..."
# Terraform modules/pubsub/main.tf の event_subscribers と完全一致
declare -A EVENT_SUBSCRIBERS=(
  ["market-collect-requested"]="data-collector audit-log"
  ["market-collected"]="feature-engineering audit-log"
  ["market-collect-failed"]="audit-log"
  ["features-generated"]="signal-generator audit-log"
  ["features-generation-failed"]="audit-log"
  ["signal-generated"]="portfolio-planner audit-log"
  ["signal-generation-failed"]="audit-log"
  ["orders-proposed"]="risk-guard audit-log"
  ["orders-proposal-failed"]="audit-log"
  ["orders-approved"]="execution audit-log"
  ["orders-rejected"]="audit-log"
  ["orders-executed"]="audit-log"
  ["orders-execution-failed"]="audit-log"
  ["operation-kill-switch-changed"]="risk-guard audit-log"
  ["insight-collect-requested"]="insight-collector audit-log"
  ["insight-collected"]="agent-orchestrator audit-log"
  ["insight-collect-failed"]="audit-log"
  ["hypothesis-retest-requested"]="agent-orchestrator audit-log"
  ["hypothesis-proposed"]="hypothesis-lab audit-log"
  ["hypothesis-proposal-failed"]="audit-log"
  ["hypothesis-demo-completed"]="hypothesis-lab audit-log"
  ["hypothesis-backtested"]="audit-log"
  ["hypothesis-promoted"]="audit-log"
  ["hypothesis-rejected"]="audit-log"
)

# サブスクライバーなしトピック（publisher readiness のため作成）
SUBSCRIBER_LESS_TOPICS=("audit-recorded")

# サービス名からpush endpointのURLを解決する
resolve_push_url() {
  local subscriber="$1"
  case "${subscriber}" in
    "bff")                 echo "${BFF_URL}/pubsub/push" ;;
    "data-collector")      echo "${DATA_COLLECTOR_URL}/pubsub/push" ;;
    "feature-engineering") echo "${FEATURE_ENGINEERING_URL}/pubsub/push" ;;
    "signal-generator")    echo "${SIGNAL_GENERATOR_URL}/pubsub/push" ;;
    "portfolio-planner")   echo "${PORTFOLIO_PLANNER_URL}/pubsub/push" ;;
    "risk-guard")          echo "${RISK_GUARD_URL}/pubsub/push" ;;
    "execution")           echo "${EXECUTION_URL}/pubsub/push" ;;
    "audit-log")           echo "${AUDIT_LOG_URL}/pubsub/push" ;;
    "insight-collector")   echo "${INSIGHT_COLLECTOR_URL}/pubsub/push" ;;
    "agent-orchestrator")  echo "${AGENT_ORCHESTRATOR_URL}/pubsub/push" ;;
    "hypothesis-lab")      echo "${HYPOTHESIS_LAB_URL}/pubsub/push" ;;
    *)                     echo "http://${subscriber}:8080/pubsub/push" ;;
  esac
}

create_topic() {
  local topic_name="$1"
  local url="${BASE_URL}/v1/projects/${PROJECT_ID}/topics/${topic_name}"
  local http_status
  http_status=$(curl_status -X PUT \
    -H "Content-Type: application/json" \
    "${url}")
  if [[ "${http_status}" == "200" ]]; then
    echo "  [created] topic: ${topic_name}"
  elif [[ "${http_status}" == "409" ]]; then
    echo "  [exists]  topic: ${topic_name}"
  else
    echo "  [ERROR]   topic: ${topic_name} (HTTP ${http_status})" >&2
    return 1
  fi
}

create_subscription() {
  local subscription_name="$1"
  local topic_name="$2"
  local push_endpoint="$3"  # 空文字列の場合は pull subscription（pushConfig なし）
  local url="${BASE_URL}/v1/projects/${PROJECT_ID}/subscriptions/${subscription_name}"
  local body
  if [[ -n "${push_endpoint}" ]]; then
    body=$(cat <<JSON
{
  "topic": "projects/${PROJECT_ID}/topics/${topic_name}",
  "ackDeadlineSeconds": 60,
  "messageRetentionDuration": "604800s",
  "pushConfig": {
    "pushEndpoint": "${push_endpoint}"
  }
}
JSON
)
  else
    # DLQサブスクリプションは pull モード（手動検査・再送用）
    body=$(cat <<JSON
{
  "topic": "projects/${PROJECT_ID}/topics/${topic_name}",
  "ackDeadlineSeconds": 60,
  "messageRetentionDuration": "604800s"
}
JSON
)
  fi
  local http_status
  http_status=$(curl_status -X PUT \
    -H "Content-Type: application/json" \
    -d "${body}" \
    "${url}")
  if [[ "${http_status}" == "200" ]]; then
    if [[ -n "${push_endpoint}" ]]; then
      echo "  [created] subscription: ${subscription_name} -> ${push_endpoint}"
    else
      echo "  [created] subscription: ${subscription_name} (pull)"
    fi
  elif [[ "${http_status}" == "409" ]]; then
    echo "  [exists]  subscription: ${subscription_name}"
  else
    echo "  [ERROR]   subscription: ${subscription_name} (HTTP ${http_status})" >&2
    return 1
  fi
}

echo "==> Initializing Pub/Sub emulator (project: ${PROJECT_ID})"
echo "    Host: ${BASE_URL}"
echo ""

# サブスクライバーなしトピックを作成する
echo "--- Subscriber-less topics ---"
for event_type in "${SUBSCRIBER_LESS_TOPICS[@]}"; do
  topic_name="event-${event_type}-v1"
  create_topic "${topic_name}"
done
echo ""

# イベント配線のトピックとサブスクリプションを作成する
for event_type in "${!EVENT_SUBSCRIBERS[@]}"; do
  topic_name="event-${event_type}-v1"
  echo "--- ${topic_name} ---"
  create_topic "${topic_name}"

  subscribers_str="${EVENT_SUBSCRIBERS[${event_type}]}"
  read -ra subscribers <<< "${subscribers_str}"
  for subscriber in "${subscribers[@]}"; do
    sub_name="sub-${subscriber}-event-${event_type}-v1"
    dlq_topic_name="dlq-${subscriber}-event-${event_type}-v1"
    dlq_sub_name="sub-dlq-${subscriber}-event-${event_type}-v1"
    push_endpoint=$(resolve_push_url "${subscriber}")

    # DLQトピックを先に作成する（サブスクリプションのDLQポリシーが参照するため）
    create_topic "${dlq_topic_name}"

    # メインサブスクリプションを作成する
    create_subscription "${sub_name}" "${topic_name}" "${push_endpoint}"

    # DLQサブスクリプション（手動検査・再送用）はpush endpointなし
    create_subscription "${dlq_sub_name}" "${dlq_topic_name}" ""
  done
  echo ""
done

echo "==> Pub/Sub initialization complete."
