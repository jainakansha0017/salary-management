import { NavLink, Navigate, Route, Routes } from "react-router-dom";
import { DirectoryPage } from "./pages/DirectoryPage";
import { EmployeePage } from "./pages/EmployeePage";
import { AnalyticsPage } from "./pages/AnalyticsPage";

export function App() {
  return (
    <div className="app">
      <header className="app__bar">
        <span className="app__brand">
          ACME <strong>Salary</strong>
        </span>
        <nav className="app__nav" aria-label="Main">
          <NavLink to="/employees" className={navLinkClass}>
            Directory
          </NavLink>
          <NavLink to="/analytics" className={navLinkClass}>
            Analytics
          </NavLink>
        </nav>
      </header>

      <main className="app__main">
        <Routes>
          <Route path="/" element={<Navigate to="/employees" replace />} />
          <Route path="/employees" element={<DirectoryPage />} />
          <Route path="/employees/:id" element={<EmployeePage />} />
          <Route path="/analytics" element={<AnalyticsPage />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </main>
    </div>
  );
}

function navLinkClass({ isActive }: { isActive: boolean }): string {
  return isActive ? "app__nav-link app__nav-link--active" : "app__nav-link";
}

function NotFound() {
  return (
    <div className="notice">
      <h1 className="notice__title">No such page</h1>
      <p className="notice__body">
        <NavLink to="/employees">Back to the directory</NavLink>
      </p>
    </div>
  );
}
