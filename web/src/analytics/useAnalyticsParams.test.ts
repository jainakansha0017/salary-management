import { describe, expect, it } from "vitest";
import { fromSearchParams } from "./useAnalyticsParams";

function read(query: string) {
  return fromSearchParams(new URLSearchParams(query));
}

describe("fromSearchParams", () => {
  it("defaults to today and to the department breakdown", () => {
    const params = read("");

    // Empty, not today's date: the server already defaults to today, and
    // writing the date in would freeze a shared link to the day it was sent.
    expect(params.as_of).toBe("");
    expect(params.dimension).toBe("department");
  });

  it("reads the filters back as the arrays the API takes", () => {
    const params = read("country_code=PL&country_code=IN&department_id=11&job_level=L5");

    expect(params.country_code).toEqual(["PL", "IN"]);
    expect(params.department_id).toEqual([11]);
    expect(params.job_level).toEqual(["L5"]);
  });

  it("keeps a date someone asked for", () => {
    expect(read("as_of=2026-01-01").as_of).toBe("2026-01-01");
  });

  // A URL someone edited, or a link that rotted. The server would answer by
  // department anyway, so agreeing with it keeps the control and the table
  // below it telling the same story.
  it("falls back to department for a dimension it does not group by", () => {
    expect(read("dimension=favourite_colour").dimension).toBe("department");
    expect(read("dimension=job_level").dimension).toBe("job_level");
  });

  it("drops a department id that is not a number", () => {
    expect(read("department_id=11&department_id=banana").department_id).toEqual([11]);
  });
});
