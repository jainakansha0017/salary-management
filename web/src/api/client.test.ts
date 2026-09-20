import { describe, expect, it } from "vitest";
import { toQuery } from "./client";

// Decoded before asserting: `URLSearchParams` percent-escapes the brackets, and
// `?country_code%5B%5D=PL` is unreadable as a statement of the contract.
function query(params: object): string {
  return decodeURIComponent(toQuery(params));
}

describe("toQuery", () => {
  // This is the contract with Rails' `permit(country_code: [])`. Sending
  // `country_code=PL&country_code=DE` instead would arrive as the single
  // string "DE", and the page would silently filter by one country.
  it("sends a repeated parameter in the bracketed form Rails expects", () => {
    expect(query({ country_code: ["PL", "DE"] })).toBe("?country_code[]=PL&country_code[]=DE");
  });

  it("escapes a value that would otherwise become a second parameter", () => {
    expect(toQuery({ q: "a&b=c" })).toBe("?q=a%26b%3Dc");
  });

  // An absent filter must not be sent at all: `?q=` is a search for the empty
  // string, which the server would echo back as an applied filter.
  it("omits values that mean 'no filter' rather than sending them empty", () => {
    expect(query({ q: "", status: undefined, sort: null, page: 2 })).toBe("?page=2");
  });

  it("produces nothing at all when there is nothing to ask for", () => {
    expect(toQuery({})).toBe("");
  });

  // Zero and false are answers, not absences.
  it("keeps a falsy value that is still a value", () => {
    expect(query({ page: 0, department_id: [0] })).toBe("?page=0&department_id[]=0");
  });
});
