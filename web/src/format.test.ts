import { describe, expect, it } from "vitest";
import {
  NOT_APPLICABLE,
  formatDate,
  formatMoney,
  formatMoneyCompact,
  formatMoneyOrDash,
  formatReason,
  toMinorUnits,
} from "./format";
import type { Money } from "./api/types";

function money(amount_minor: number, currency_code = "USD", minor_unit = 2): Money {
  return { amount_minor, currency_code, minor_unit };
}

describe("formatMoney", () => {
  it("reads the scale from the amount rather than assuming two decimals", () => {
    expect(formatMoney(money(12_000_055))).toBe("$120,000.55");
    expect(formatMoney(money(15_000_000, "JPY", 0))).toBe("¥15,000,000");
  });

  // The whole reason the exponent travels with the amount: assuming two
  // decimals would show a ¥15m salary as ¥150,000.
  it("does not divide a zero-decimal currency by a hundred", () => {
    expect(formatMoney(money(15_000_000, "JPY", 0))).not.toContain("150,000.00");
  });

  // The separator is U+00A0, not a space, and that is correct: the code must
  // not wrap onto a different line from its amount. Written as an escape here
  // because the two are indistinguishable in a diff, and a failure message
  // comparing them reads as "expected X to be X".
  it("labels a currency it has no symbol for, and keeps the label attached", () => {
    expect(formatMoney(money(17_260_000, "PLN"))).toBe("PLN\u00A0172,600.00");
  });

  it("keeps the minor units that a rounded display would lose", () => {
    expect(formatMoney(money(99_999_999))).toBe("$999,999.99");
  });
});

describe("formatMoneyCompact", () => {
  it("shortens a figure that is a chart label rather than a number to check", () => {
    expect(formatMoneyCompact(money(45_000_000))).toBe("$450K");
    expect(formatMoneyCompact(money(123_456_700))).toBe("$1.2M");
  });

  // A tick reading `$450.0K` is the default and looks like a mistake.
  it("drops a trailing zero rather than padding the label", () => {
    expect(formatMoneyCompact(money(99_900))).toBe("$999");
  });
});

describe("formatMoneyOrDash", () => {
  // Someone who has left has no current salary, which is not the same as being
  // paid nothing — and an empty cell reads as a bug.
  it("shows a dash for absent pay rather than a zero or a blank", () => {
    expect(formatMoneyOrDash(null)).toBe(NOT_APPLICABLE);
    expect(formatMoneyOrDash(money(0))).toBe("$0.00");
  });
});

describe("formatDate", () => {
  // `new Date("2026-10-01")` is midnight UTC, which is the previous day for
  // anyone west of Greenwich. An effective date that renders a day early is a
  // wrong answer about when someone's pay changed.
  it("does not shift a calendar date into the day before", () => {
    expect(formatDate("2026-10-01")).toBe("Oct 1, 2026");
    expect(formatDate("2026-01-01")).toBe("Jan 1, 2026");
  });

  it("shows a dash for an open-ended period rather than an empty cell", () => {
    expect(formatDate(null)).toBe(NOT_APPLICABLE);
  });

  it("returns something unparseable unchanged instead of showing NaN", () => {
    expect(formatDate("not a date")).toBe("not a date");
  });
});

describe("formatReason", () => {
  it("turns the domain's vocabulary into English", () => {
    expect(formatReason("merit_increase")).toBe("Merit increase");
  });

  // A reason added to the server without a change here should read acceptably
  // rather than appear blank.
  it("handles a reason it has never seen", () => {
    expect(formatReason("cost_of_living_adjustment")).toBe("Cost of living adjustment");
  });
});

describe("toMinorUnits", () => {
  it("shifts the decimal point rather than multiplying", () => {
    expect(toMinorUnits("95000.50", 2)).toBe(9_500_050);
    expect(toMinorUnits("95000", 2)).toBe(9_500_000);
    expect(toMinorUnits("95000.5", 2)).toBe(9_500_050);
  });

  // `95000.55 * 100` is 9500054.999999999 in IEEE-754, so a multiply-and-round
  // implementation of this loses a penny on exactly the kind of figure a salary
  // is. Three values that all round the wrong way.
  it("is exact where floating-point multiplication is not", () => {
    expect(toMinorUnits("95000.55", 2)).toBe(9_500_055);
    expect(toMinorUnits("1.15", 2)).toBe(115);
    expect(toMinorUnits("80.29", 2)).toBe(8029);
  });

  it("honours the currency's own exponent", () => {
    expect(toMinorUnits("15000000", 0)).toBe(15_000_000);
    expect(toMinorUnits("125.500", 3)).toBe(125_500);
  });

  // Not truncated to ¥15,000: a figure typed with decimals the currency does
  // not have is a mistake, and quietly dropping it changes someone's pay.
  it("refuses more precision than the currency has", () => {
    expect(toMinorUnits("15000.75", 0)).toBeNull();
    expect(toMinorUnits("100.999", 2)).toBeNull();
  });

  it("accepts a figure pasted out of a spreadsheet", () => {
    expect(toMinorUnits(" 1,250,000.00 ", 2)).toBe(125_000_000);
  });

  it("rejects anything that is not a positive amount", () => {
    expect(toMinorUnits("", 2)).toBeNull();
    expect(toMinorUnits("0", 2)).toBeNull();
    expect(toMinorUnits("-500", 2)).toBeNull();
    expect(toMinorUnits("1e5", 2)).toBeNull();
    expect(toMinorUnits("ninety thousand", 2)).toBeNull();
    expect(toMinorUnits("95_000", 2)).toBeNull();
  });
});
