# docker/Makefile
# ローカル開発環境の操作コマンド集。
# 使い方: make <target>

COMPOSE_FILE := docker-compose.yml
ENV_FILE     := .env.local
COMPOSE      := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)

.PHONY: help up down init build build-service logs logs-service restart restart-service ps clean generate-jwt-keys

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
	$(COMPOSE) build

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
