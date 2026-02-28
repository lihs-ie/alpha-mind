const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isValidEmail(value: string): boolean {
  return EMAIL_REGEX.test(value);
}

export function isValidUuid(value: string): boolean {
  return UUID_REGEX.test(value);
}

export function isValidDateRange(from: string, to: string): boolean {
  if (!from || !to) return true;
  return new Date(from) <= new Date(to);
}

export function isInRange(value: number, min: number, max: number): boolean {
  return value > min && value <= max;
}

export function isInIntegerRange(value: number, min: number, max: number): boolean {
  return Number.isInteger(value) && value >= min && value <= max;
}
