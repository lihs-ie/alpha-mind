"""Hypothesis Lab service entrypoint."""

from __future__ import annotations

import logging
import os

from presentation.app_factory import create_application
from presentation.dependency_container import DependencyContainer

logging.basicConfig(level=logging.INFO)


def main() -> None:
    """Build the DI container, create the Flask application, and start the server."""
    container = DependencyContainer()
    application = create_application(container.hypothesis_workflow_service())
    port = int(os.environ.get("PORT", "8080"))
    application.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
