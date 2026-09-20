import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// jsdom is reused across the files in a worker, so a component left mounted by
// one test can be found by the next one and make it pass for the wrong reason.
afterEach(cleanup);
