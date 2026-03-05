# docker/Makefile
# ローカル開発環境の操作コマンド集。
# 使い方: make <target>

COMPOSE_FILE := docker-compose.yml
ENV_FILE     := .env.local
COMPOSE      := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)
INTEGRATION_DIR  := integration
INTEGRATION_BASE := $(INTEGRATION_DIR)/docker-compose.integration.base.yml

.PHONY: help up down init build build-service logs logs-service restart restart-service ps clean generate-jwt-keys integration-up integration-down integration-logs integration-ps

help: ## このヘルプを表示する
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

generate-jwt-keys: ## JWT RS256 鍵ペアを生成する（既存なればスキップ）
	bash scripts/generate-jwt-keys.sh

up: generate-jwt-keys ## 全サービスを起動する（エミュレータ → init → アプリ）
	$(COMPOSE) up -d

down: ## 全サービスを停止・削除する
	$(COMPOSE) down

clean: ## 全サービスを停止し、ボリューム・ローカルイメージも削除する
	$(COMPOSE) down -v --rmi local --remove-orphans

init: ## エミュレータのみ起動し、初期化スクリプトを手動実行する
	$(COMPOSE) up -d firestore pubsub gcs
	@echo "Waiting for emulators to be healthy..."
	$(COMPOSE) up --wait firestore pubsub gcs
	$(COMPOSE) run --rm init

build: ## 全サービスの Docker イメージをビルドする
	DOCKER_BUILDKIT=1 $(COMPOSE) build

build-service: ## 特定サービスのイメージをビルドする (例: make build-service SERVICE=bff)
	$(COMPOSE) build $(SERVICE)

logs: ## 全サービスのログを tail する
	$(COMPOSE) logs -f

logs-service: ## 特定サービスのログを tail する (例: make logs-service SERVICE=bff)
	$(COMPOSE) logs -f $(SERVICE)

restart: ## 全サービスを再起動する
	$(COMPOSE) restart

restart-service: ## 特定サービスを再起動する (例: make restart-service SERVICE=bff)
	$(COMPOSE) restart $(SERVICE)

ps: ## 実行中サービスの一覧を表示する
	$(COMPOSE) ps

integration-up: generate-jwt-keys ## サービス別統合テスト構成を起動する (例: make integration-up SERVICE=bff)
	@test -n "$(SERVICE)" || (echo "SERVICE is required (e.g. SERVICE=bff)"; exit 1)
	@test -f "$(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml" || (echo "Unknown SERVICE: $(SERVICE)"; exit 1)
	docker compose --env-file $(ENV_FILE) \
	  -f $(INTEGRATION_BASE) \
	  -f $(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml \
	  up -d --build

integration-down: ## サービス別統合テスト構成を停止する (例: make integration-down SERVICE=bff)
	@test -n "$(SERVICE)" || (echo "SERVICE is required (e.g. SERVICE=bff)"; exit 1)
	@test -f "$(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml" || (echo "Unknown SERVICE: $(SERVICE)"; exit 1)
	docker compose --env-file $(ENV_FILE) \
	  -f $(INTEGRATION_BASE) \
	  -f $(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml \
	  down --remove-orphans

integration-logs: ## サービス別統合テスト構成のログを表示する (例: make integration-logs SERVICE=bff)
	@test -n "$(SERVICE)" || (echo "SERVICE is required (e.g. SERVICE=bff)"; exit 1)
	@test -f "$(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml" || (echo "Unknown SERVICE: $(SERVICE)"; exit 1)
	docker compose --env-file $(ENV_FILE) \
	  -f $(INTEGRATION_BASE) \
	  -f $(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml \
	  logs -f

integration-ps: ## サービス別統合テスト構成のプロセスを表示する (例: make integration-ps SERVICE=bff)
	@test -n "$(SERVICE)" || (echo "SERVICE is required (e.g. SERVICE=bff)"; exit 1)
	@test -f "$(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml" || (echo "Unknown SERVICE: $(SERVICE)"; exit 1)
	docker compose --env-file $(ENV_FILE) \
	  -f $(INTEGRATION_BASE) \
	  -f $(INTEGRATION_DIR)/docker-compose.integration.$(SERVICE).yml \
	  ps
