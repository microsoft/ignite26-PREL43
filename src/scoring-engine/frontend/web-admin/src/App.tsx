import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import type { ReactNode } from "react";
import Layout from "./components/Layout";
import { isSignedIn } from "./lib/auth";
import Dashboard from "./pages/Dashboard";
import EventDetailPage from "./pages/EventDetail";
import Events from "./pages/Events";
import Integrations from "./pages/Integrations";
import Login from "./pages/Login";
import System from "./pages/System";

function Protected({ children }: { children: ReactNode }) {
  return isSignedIn() ? <>{children}</> : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={
            <Protected>
              <Layout />
            </Protected>
          }
        >
          <Route index element={<Dashboard />} />
          <Route path="events" element={<Events />} />
          <Route path="events/:eventId" element={<EventDetailPage />} />
          <Route path="integrations" element={<Integrations />} />
          <Route path="system" element={<System />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
