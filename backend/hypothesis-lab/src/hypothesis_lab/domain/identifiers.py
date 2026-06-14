"""Identifier types for hypothesis-lab domain aggregates."""

from typing import NewType

HypothesisIdentifier = NewType("HypothesisIdentifier", str)
ValidationRunIdentifier = NewType("ValidationRunIdentifier", str)
FailureKnowledgeIdentifier = NewType("FailureKnowledgeIdentifier", str)
