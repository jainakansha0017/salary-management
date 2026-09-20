import type { Money } from "./api/types";

/**
 * One locale for the whole application, rather than the browser's.
 *
 * A figure quoted in a meeting should read identically to everyone looking at
 * it, and a salary is exactly the kind of number that gets read out. It also
 * makes the tests deterministic instead of dependent on the machine running
 * them. Changing it is this line.
 */
const LOCALE = "en-US";

/**
 * The exponent comes from the payload, never from the currency code (ADR-6), so
 * JPY renders with no decimals and an API that starts reporting a currency this
 * client has never seen needs no change here.
 *
 * The division to major units is the one place a float touches money, and it is
 * the last thing that happens before the string. No arithmetic is done on the
 * result — differences and totals are the server's job, computed on integers.
 * Salaries are many orders of magnitude below the point where a double stops
 * representing an exact integer, so the rounding Intl does is the only rounding
 * there is.
 */
export function formatMoney(money: Money): string {
  return currencyFormatter(money.currency_code, money.minor_unit).format(toMajorUnits(money));
}

/**
 * For axis labels and chart ticks, where `$450,000.00` is six characters of
 * noise and `$450K` is the same information.
 */
export function formatMoneyCompact(money: Money): string {
  return compactFormatter(money.currency_code).format(toMajorUnits(money));
}

/** An em dash, because a blank cell reads as a rendering failure. */
export const NOT_APPLICABLE = "—";

export function formatMoneyOrDash(money: Money | null | undefined): string {
  return money ? formatMoney(money) : NOT_APPLICABLE;
}

/**
 * Dates arrive as `YYYY-MM-DD` and mean a calendar day, not an instant.
 * `new Date("2026-10-01")` parses as midnight UTC, which is the 30th of
 * September for anyone west of Greenwich — so the parts are read directly
 * rather than handed to a timezone.
 */
export function formatDate(iso: string | null | undefined): string {
  if (!iso) return NOT_APPLICABLE;

  const [year, month, day] = iso.split("-").map(Number);
  if (!year || !month || !day) return iso;

  return dateFormatter.format(new Date(Date.UTC(year, month - 1, day)));
}

export function formatNumber(value: number): string {
  return numberFormatter.format(value);
}

/**
 * `hire` and `merit_increase` are the server's vocabulary. This is the one
 * place they become English, so a new reason added to the domain shows up as a
 * readable fallback rather than as a crash or a blank.
 */
export function formatReason(reason: string): string {
  return reason.replace(/_/g, " ").replace(/^./, (character) => character.toUpperCase());
}

function toMajorUnits(money: Money): number {
  return money.amount_minor / 10 ** money.minor_unit;
}

// `Intl.NumberFormat` is not cheap to construct and a table builds one per
// cell, so the formatters are made once per shape and reused.
const formatters = new Map<string, Intl.NumberFormat>();

function currencyFormatter(currency: string, minorUnit: number): Intl.NumberFormat {
  return cached(`currency:${currency}:${minorUnit}`, () =>
    new Intl.NumberFormat(LOCALE, {
      style: "currency",
      currency,
      minimumFractionDigits: minorUnit,
      maximumFractionDigits: minorUnit,
    }),
  );
}

function compactFormatter(currency: string): Intl.NumberFormat {
  return cached(`compact:${currency}`, () =>
    new Intl.NumberFormat(LOCALE, {
      style: "currency",
      currency,
      notation: "compact",
      // Both, not just the maximum: `maximumFractionDigits` alone still emits
      // `$450.0K`, because compact notation defaults the minimum to match.
      maximumFractionDigits: 1,
      minimumFractionDigits: 0,
    }),
  );
}

function cached(key: string, build: () => Intl.NumberFormat): Intl.NumberFormat {
  const existing = formatters.get(key);
  if (existing) return existing;

  const created = build();
  formatters.set(key, created);
  return created;
}

const dateFormatter = new Intl.DateTimeFormat(LOCALE, {
  day: "numeric",
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

const numberFormatter = new Intl.NumberFormat(LOCALE);
