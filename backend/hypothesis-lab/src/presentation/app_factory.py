"""Flask application factory for hypothesis-lab service.

Creates and configures the Flask application with health check and
Pub/Sub subscriber blueprints.
"""

from __future__ import annotations

import flask

from application.hypothesis_workflow_service import HypothesisWorkflowService
from presentation.health import health_blueprint
from presentation.subscriber import subscriber_blueprint


def create_application(hypothesis_workflow_service: HypothesisWorkflowService) -> flask.Flask:
    """Create a Flask application with all blueprints registered.

    Args:
        hypothesis_workflow_service: The wired application service to handle events.

    Returns:
        A configured Flask application.
    """
    application = flask.Flask("hypothesis-lab")
    application.config["HYPOTHESIS_WORKFLOW_SERVICE"] = hypothesis_workflow_service

    application.register_blueprint(health_blueprint)
    application.register_blueprint(subscriber_blueprint)

    return application
