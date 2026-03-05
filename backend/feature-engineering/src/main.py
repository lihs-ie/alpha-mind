"""Feature Engineering service entry point.

Creates the DI container, wires the FeatureGenerationService, and
starts the Flask application to receive Pub/Sub push messages.
"""

from __future__ import annotations

import os

from presentation.app_factory import create_application
from presentation.dependency_container import DependencyContainer


def main() -> None:
    """Start the feature-engineering service."""
    port = int(os.environ.get("PORT", "8080"))

    container = DependencyContainer()
    service = container.feature_generation_service()
    application = create_application(service)

    application.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
