"""Domain exceptions for hypothesis-lab."""


class HypothesisLabDomainError(Exception):
    """hypothesis-lab ドメイン層の基底例外クラス。"""


class InvalidStateTransitionError(HypothesisLabDomainError):
    """許可されていない状態遷移が試みられた場合に送出される例外。"""


class InvariantViolationError(HypothesisLabDomainError):
    """不変条件に違反した場合に送出される例外。"""


class OperationNotAllowedError(HypothesisLabDomainError):
    """現在の状態では許可されていない操作が試みられた場合に送出される例外。"""
