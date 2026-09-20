import { describe, expect, it } from "vitest";
import { fromSearchParams, nextSort } from "./useDirectoryParams";

function read(query: string) {
  return fromSearchParams(new URLSearchParams(query));
}

describe("reading the directory's state out of the URL", () => {
  it("defaults to active employees sorted by name", () => {
    expect(read("")).toMatchObject({
      status: "active",
      sort: "name",
      direction: "asc",
      page: 1,
    });
  });

  it("collects a facet chosen more than once", () => {
    expect(read("country_code=PL&country_code=IN").country_code).toEqual(["PL", "IN"]);
  });

  it("reads department ids as numbers, because that is what the API matches on", () => {
    expect(read("department_id=11&department_id=14").department_id).toEqual([11, 14]);
  });

  // A URL someone edited, or a link that rotted. Showing the first page shows
  // them something; NaN in the query string would show them an error.
  it.each(["page=0", "page=-3", "page=banana", "page="])(
    "falls back to page 1 for ?%s",
    (query) => {
      expect(read(query).page).toBe(1);
    },
  );

  it("ignores a department id that is not a number rather than sending NaN", () => {
    expect(read("department_id=11&department_id=oops").department_id).toEqual([11]);
  });

  // The direction is left out of the URL when it is the column's own default,
  // so reading it back has to apply that same default. A blanket "asc" here
  // turns a click on Salary into an ascending sort.
  it("reads a bare ?sort=salary as the descending sort that wrote it", () => {
    expect(read("sort=salary").direction).toBe("desc");
    expect(read("sort=hired_on").direction).toBe("desc");
    expect(read("sort=salary&direction=asc").direction).toBe("asc");
  });
});

describe("choosing the next sort", () => {
  it("reverses the direction when the column is already the one being sorted", () => {
    expect(nextSort({ sort: "name", direction: "asc" }, "name")).toEqual({
      sort: "name",
      direction: "desc",
    });
  });

  // Nobody asks who is paid least, or who was hired longest ago, first.
  it("starts pay and hire date at the interesting end", () => {
    expect(nextSort({ sort: "name", direction: "asc" }, "salary").direction).toBe("desc");
    expect(nextSort({ sort: "name", direction: "asc" }, "hired_on").direction).toBe("desc");
  });

  it("starts a name sort at A", () => {
    expect(nextSort({ sort: "salary", direction: "desc" }, "name").direction).toBe("asc");
  });
});
