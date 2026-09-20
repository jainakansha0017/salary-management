import { useState } from "react";
import type { FormEvent } from "react";
import { ApiError } from "../api/client";
import type { CompensationReason, Money } from "../api/types";
import { toMinorUnits } from "../format";
import { useRecordSalaryChange } from "./api";

interface Props {
  employeeId: string;
  /** The pay this change replaces — it fixes the currency and its exponent. */
  currency: Money;
}

/**
 * `hire` is deliberately missing. It is the reason the first period carries,
 * written when the employee is created; offering it here would let someone
 * record a second hiring for a person already employed.
 */
const REASONS: { value: CompensationReason; label: string }[] = [
  { value: "merit_increase", label: "Merit increase" },
  { value: "promotion", label: "Promotion" },
  { value: "market_adjustment", label: "Market adjustment" },
  { value: "correction", label: "Correction" },
];

/**
 * Records a new salary. There is no edit and no delete, here or on the server:
 * pay history is append-only, and a mistake is fixed by recording a correction
 * (ADR-2). That is why this is a "record a change" form and not an "edit
 * salary" form — the wording is the model, not decoration.
 */
export function SalaryChangeForm({ employeeId, currency }: Props) {
  const [amount, setAmount] = useState("");
  const [effectiveFrom, setEffectiveFrom] = useState(todayIso());
  const [reason, setReason] = useState<CompensationReason>("merit_increase");
  const [note, setNote] = useState("");
  const [amountProblem, setAmountProblem] = useState<string | null>(null);

  const record = useRecordSalaryChange(employeeId);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    // Checked here rather than left to the server, because the server's
    // vocabulary for this is minor units — an implementation detail the person
    // typing a salary has no reason to know about.
    const amountMinor = toMinorUnits(amount, currency.minor_unit);
    if (amountMinor === null) {
      setAmountProblem(
        currency.minor_unit > 0
          ? `Enter a positive amount, to at most ${currency.minor_unit} decimal places.`
          : "Enter a positive whole amount.",
      );
      return;
    }
    setAmountProblem(null);

    record.mutate(
      {
        amount_minor: amountMinor,
        currency_code: currency.currency_code,
        effective_from: effectiveFrom,
        reason,
        ...(note.trim() ? { note: note.trim() } : {}),
      },
      // Only the amount and note are cleared. The date and reason are the
      // fields most likely to be the same for the next person, and retyping
      // them is how the wrong date gets entered.
      {
        onSuccess: () => {
          setAmount("");
          setNote("");
        },
      },
    );
  }

  return (
    <form className="form" onSubmit={handleSubmit} noValidate>
      <h2 className="card__title">Record a salary change</h2>

      <div className="form__row">
        <Field
          id="salary-amount"
          label={`New salary (${currency.currency_code})`}
          problems={amountProblem ? [amountProblem] : serverProblems(record.error, "amount_minor")}
        >
          <input
            id="salary-amount"
            className="input"
            // Not `type="number"`: a scroll wheel over a focused number input
            // changes a salary, and the spinner arrows invite the same mistake.
            type="text"
            inputMode="decimal"
            autoComplete="off"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
          />
        </Field>

        <Field
          id="salary-effective-from"
          label="Effective from"
          problems={serverProblems(record.error, "effective_from")}
        >
          <input
            id="salary-effective-from"
            className="input"
            type="date"
            value={effectiveFrom}
            onChange={(event) => setEffectiveFrom(event.target.value)}
          />
        </Field>

        <Field id="salary-reason" label="Reason" problems={serverProblems(record.error, "reason")}>
          <select
            id="salary-reason"
            className="input"
            value={reason}
            onChange={(event) => setReason(event.target.value as CompensationReason)}
          >
            {REASONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <Field
        id="salary-note"
        label="Note (optional)"
        problems={serverProblems(record.error, "note")}
      >
        <input
          id="salary-note"
          className="input form__wide"
          type="text"
          value={note}
          onChange={(event) => setNote(event.target.value)}
          placeholder="Approved by, ticket reference, anything the next person will want"
        />
      </Field>

      <div className="form__actions">
        <button type="submit" className="button button--primary" disabled={record.isPending}>
          {record.isPending ? "Recording…" : "Record change"}
        </button>

        {record.isSuccess && (
          <span className="form__ok" role="status">
            Change recorded.
          </span>
        )}
      </div>

      {/* A rejection that does not belong to one field — a missing exchange
          rate, a lost connection — still has to be said somewhere. */}
      {record.isError && generalProblem(record.error) && (
        <p className="form__error" role="alert">
          {generalProblem(record.error)}
        </p>
      )}
    </form>
  );
}

function Field({
  id,
  label,
  problems,
  children,
}: {
  id: string;
  label: string;
  problems: string[];
  children: React.ReactNode;
}) {
  return (
    <div className="form__field">
      <label className="filters__label" htmlFor={id}>
        {label}
      </label>
      {children}
      {problems.map((problem) => (
        <p key={problem} className="form__error" role="alert">
          {problem}
        </p>
      ))}
    </div>
  );
}

/**
 * The API reports validation failures keyed by field, which is what lets the
 * message sit under the input that caused it rather than in a list at the top
 * that leaves the reader to work out which box is wrong.
 */
function serverProblems(error: unknown, field: string): string[] {
  if (!(error instanceof ApiError)) return [];

  return error.details[field] ?? [];
}

/** Whatever the failure was, if no single field owns it. */
function generalProblem(error: unknown): string | null {
  if (!(error instanceof ApiError)) return "Could not reach the server.";
  if (Object.keys(error.details).length > 0) return null;

  return error.message;
}

/**
 * The browser's local date, not UTC. "Today" for someone in Kolkata is not the
 * same day as `toISOString()` gives them for five and a half hours each night,
 * and this value is a calendar day rather than an instant.
 */
function todayIso(): string {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");

  return `${now.getFullYear()}-${month}-${day}`;
}
