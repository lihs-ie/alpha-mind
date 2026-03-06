"""Flask application factory for feature-engineering service.

Creates and configures the Flask application with health check and
Pub/Sub subscriber blueprints.
"""

from __future__ import annotations

import flask

from presentation.health import health_blueprint
from presentation.subscriber import subscriber_blueprint
from usecase.feature_generation_service import FeatureGenerationService


def create_application(feature_generation_service: FeatureGenerationService) -> flask.Flask:
    """Create a Flask application with all blueprints registered.

    Args:
        feature_generation_service: The wired usecase service to handle events.

    Returns:
        A configured Flask application.
    """
    application = flask.Flask("feature-engineering")
    application.config["FEATURE_GENERATION_SERVICE"] = feature_generation_service

    application.register_blueprint(health_blueprint)
    application.register_blueprint(subscriber_blueprint)

    return application
