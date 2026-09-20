import { useEffect, useRef, useState } from "react";
import type { DirectoryParams } from "./api";
import { useDirectoryFacets } from "./api";
import type { DirectoryFacets } from "../api/types";

interface Props {
  params: DirectoryParams;
  onChange: (patch: Partial<DirectoryParams>) => void;
  onClear: () => void;
}

export function FilterPanel({ params, onChange, onClear }: Props) {
  const facets = useDirectoryFacets();

  return (
    <div className="filters">
      <SearchField value={params.q ?? ""} onChange={(q) => onChange({ q })} />

      <StatusField value={params.status ?? "active"} onChange={(status) => onChange({ status })} />

      {/* The panel does not block on its options. The search box and the table
          are usable while they load, and a failed lookup costs the facets, not
          the page. */}
      {facets.data && <Facets facets={facets.data} params={params} onChange={onChange} />}

      {hasFilters(params) && (
        <button type="button" className="filters__clear" onClick={onClear}>
          Clear all
        </button>
      )}
    </div>
  );
}

/**
 * Typing is local state; the URL is updated once the typing stops.
 *
 * Writing every keystroke to the URL would put a history entry and a request
 * behind each letter. Holding the input's value in the URL alone would make the
 * field lag behind the keyboard, because the round trip through the router is
 * not instant.
 */
function SearchField({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  const [typed, setTyped] = useState(value);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  // The URL is still the source of truth: "Clear all", the back button, or a
  // pasted link all change it from outside, and the box has to follow.
  useEffect(() => setTyped(value), [value]);

  useEffect(() => {
    if (typed === value) return;

    const timer = setTimeout(() => onChangeRef.current(typed), DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [typed, value]);

  return (
    <div className="filters__search">
      <label className="filters__label" htmlFor="directory-search">
        Search
      </label>
      <input
        id="directory-search"
        className="input"
        type="search"
        placeholder="Name, email or employee number"
        value={typed}
        onChange={(event) => setTyped(event.target.value)}
        // The server matches on a trigram index, so it is happy with two
        // characters; the browser's own "clear" button also fires this.
        autoComplete="off"
      />
    </div>
  );
}

/** Long enough that a typed word is one request, short enough to feel live. */
const DEBOUNCE_MS = 250;

/**
 * Status is a single choice rather than a facet: "active" and "departed" are
 * two different questions about the same list, not two values to combine.
 */
function StatusField({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  return (
    <div className="filters__field">
      <label className="filters__label" htmlFor="directory-status">
        Status
      </label>
      <select
        id="directory-status"
        className="input"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="active">Currently employed</option>
        <option value="departed">Departed</option>
        <option value="all">Everyone</option>
      </select>
    </div>
  );
}

function Facets({
  facets,
  params,
  onChange,
}: {
  facets: DirectoryFacets;
  params: DirectoryParams;
  onChange: (patch: Partial<DirectoryParams>) => void;
}) {
  return (
    <>
      <MultiSelect
        id="directory-country"
        label="Country"
        selected={params.country_code ?? []}
        options={facets.countries.map((code) => ({ value: code, label: code }))}
        onChange={(country_code) => onChange({ country_code })}
      />
      <MultiSelect
        id="directory-department"
        label="Department"
        selected={(params.department_id ?? []).map(String)}
        options={facets.departments.map((d) => ({
          value: String(d.id),
          label: d.name,
        }))}
        onChange={(ids) => onChange({ department_id: ids.map(Number) })}
      />
      <MultiSelect
        id="directory-level"
        label="Level"
        selected={params.job_level ?? []}
        options={facets.job_levels.map((level) => ({
          value: level,
          label: level,
        }))}
        onChange={(job_level) => onChange({ job_level })}
      />
    </>
  );
}

interface Option {
  value: string;
  label: string;
}

/**
 * A native multi-select rather than a custom dropdown.
 *
 * It is keyboard-navigable, screen-reader-labelled and familiar without any of
 * that being written here. A bespoke popover would look more modern and would
 * be where the accessibility bugs live.
 */
function MultiSelect({
  id,
  label,
  options,
  selected,
  onChange,
}: {
  id: string;
  label: string;
  options: Option[];
  selected: string[];
  onChange: (values: string[]) => void;
}) {
  return (
    <div className="filters__field">
      <label className="filters__label" htmlFor={id}>
        {label}
        {selected.length > 0 && <span className="filters__count">{selected.length}</span>}
      </label>
      <select
        id={id}
        className="input input--multi"
        multiple
        size={Math.min(options.length, 5)}
        value={selected}
        onChange={(event) =>
          onChange(Array.from(event.target.selectedOptions, (option) => option.value))
        }
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </div>
  );
}

function hasFilters(params: DirectoryParams): boolean {
  return Boolean(
    params.q ||
    (params.status && params.status !== "active") ||
    params.country_code?.length ||
    params.department_id?.length ||
    params.job_level?.length,
  );
}
