import { formatNumber } from "../format";

interface Props {
  page: number;
  totalPages: number;
  totalCount: number;
  pageSize: number;
  onGoTo: (page: number) => void;
}

/**
 * Previous and next, and the range being shown. Deliberately not a numbered
 * page list.
 *
 * At 10,000 employees that would be 383 links, which is unusable as navigation
 * and misleading as a suggestion — `OFFSET` makes the database materialise and
 * discard every row before the one asked for, so page 380 costs three times
 * page 1 (measured in docs/performance.md). The path to a distant row is to
 * search or filter for it, and that is what the page makes easy instead.
 */
export function Pagination({ page, totalPages, totalCount, pageSize, onGoTo }: Props) {
  if (totalCount === 0) return null;

  const first = (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, totalCount);

  return (
    <nav className="pagination" aria-label="Pagination">
      {/* Which rows these are, not just which page: "1–25 of 9,565" answers
          "how far in am I" without the reader doing arithmetic. */}
      <p className="pagination__range">
        {formatNumber(first)}–{formatNumber(last)} of {formatNumber(totalCount)}
      </p>

      <div className="pagination__controls">
        <button
          type="button"
          className="button"
          onClick={() => onGoTo(page - 1)}
          disabled={page <= 1}
        >
          Previous
        </button>
        <span className="pagination__position">
          Page {formatNumber(page)} of {formatNumber(totalPages)}
        </span>
        <button
          type="button"
          className="button"
          onClick={() => onGoTo(page + 1)}
          disabled={page >= totalPages}
        >
          Next
        </button>
      </div>
    </nav>
  );
}
