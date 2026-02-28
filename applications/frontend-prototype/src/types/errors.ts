import type { ProblemDetail, ReasonCode } from "./api";

export class ApiError extends Error {
  public readonly status: number;
  public readonly reasonCode: ReasonCode;
  public readonly traceId?: string;
  public readonly retryable: boolean;
  public readonly detail?: string;

  constructor(problem: ProblemDetail) {
    super(problem.title);
    this.name = "ApiError";
    this.status = problem.status;
    this.reasonCode = problem.reasonCode;
    this.traceId = problem.traceId;
    this.retryable = problem.retryable ?? false;
    this.detail = problem.detail;
  }

  get isAuthError(): boolean {
    return this.reasonCode === "AUTH_INVALID_CREDENTIALS"
      || this.reasonCode === "AUTH_TOKEN_EXPIRED"
      || this.reasonCode === "AUTH_FORBIDDEN";
  }

  get isKillSwitchError(): boolean {
    return this.reasonCode === "KILL_SWITCH_ENABLED";
  }
}
