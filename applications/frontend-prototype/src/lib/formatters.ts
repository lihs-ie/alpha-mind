const currencyFormatter = new Intl.NumberFormat("ja-JP", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const integerFormatter = new Intl.NumberFormat("ja-JP", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const percentFormatter = new Intl.NumberFormat("ja-JP", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
  style: "percent",
});

export function formatCurrency(value: number): string {
  return currencyFormatter.format(value);
}

export function formatInteger(value: number): string {
  return integerFormatter.format(value);
}

export function formatPercent(value: number): string {
  return percentFormatter.format(value / 100);
}

export function formatDecimal(value: number, fractionDigits = 2): string {
  return value.toFixed(fractionDigits);
}

export function formatDatetime(isoString: string): string {
  const date = new Date(isoString);
  return date.toLocaleString("ja-JP", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function formatDate(isoString: string): string {
  const date = new Date(isoString);
  return date.toLocaleDateString("ja-JP", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
}

export function formatPnlSign(value: number): string {
  if (value > 0) return `+${formatCurrency(value)}`;
  return formatCurrency(value);
}
