"""Signal Generator service entry point.

Flask アプリケーションの作成と起動を行う。
Cloud Run 上では gunicorn 等の WSGI サーバーから create_app() を呼び出す。
"""

from __future__ import annotations

import logging
import os

from signal_generator.presentation.dependency_container import create_application


def create_app() -> object:
    """Flask アプリケーションファクトリ。

    WSGI サーバー (gunicorn, Cloud Run) から呼び出されるエントリーポイント。
    """
    _configure_logging()
    return create_application()


def _configure_logging() -> None:
    """構造化ログの設定。"""
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    logging.basicConfig(
        level=getattr(logging, log_level, logging.INFO),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )


def main() -> None:
    """開発用のスタンドアロン起動。"""
    port = int(os.environ.get("PORT", "8080"))
    application = create_app()
    logger = logging.getLogger(__name__)
    logger.info("Signal Generator starting on port %d", port)
    application.run(host="0.0.0.0", port=port)  # type: ignore[union-attr]


if __name__ == "__main__":  # pragma: no cover
    main()
