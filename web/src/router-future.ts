/**
 * Behaviour that React Router 6 warns about and turns on by default in 7.
 *
 * Opted into now, in one place shared by the application and the test harness,
 * so the two routers behave identically and the console is not full of warnings
 * that train people to ignore the console.
 *
 * It is also the smaller half of a future upgrade to v7, which is blocked by
 * this project running Node 18. Adopting the behaviour now makes that upgrade a
 * version bump rather than a behaviour change.
 */
export const ROUTER_FUTURE = {
  v7_startTransition: true,
  v7_relativeSplatPath: true,
} as const;
