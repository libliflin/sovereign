import React from 'react';
import { BrowserRouter, Routes, Route, Link, Navigate } from 'react-router-dom';
import { KeycloakProvider, useKeycloak } from './KeycloakContext';
import Dashboard from './pages/Dashboard';
import ProjectView from './pages/ProjectView';
import StoryEditor from './pages/StoryEditor';
import PrdGenerator from './pages/PrdGenerator';
import AgentRuns from './pages/AgentRuns';

function Nav() {
  const { keycloak } = useKeycloak();
  return (
    <nav className="bg-gray-900 text-white px-6 py-3 flex items-center gap-6">
      <span className="font-bold text-lg">Sovereign PM</span>
      <Link to="/" className="hover:text-gray-300">Dashboard</Link>
      <Link to="/prd" className="hover:text-gray-300">PRD Generator</Link>
      <Link to="/runs" className="hover:text-gray-300">Agent Runs</Link>
      <div className="ml-auto">
        <button
          onClick={() => keycloak.logout()}
          className="text-sm bg-gray-700 px-3 py-1 rounded hover:bg-gray-600"
        >
          Logout
        </button>
      </div>
    </nav>
  );
}

function AuthenticatedApp() {
  const { initialized, authenticated } = useKeycloak();

  if (!initialized) {
    return <div className="flex items-center justify-center h-screen">Initializing…</div>;
  }

  if (!authenticated) {
    return <div className="flex items-center justify-center h-screen">Redirecting to login…</div>;
  }

  return (
    <BrowserRouter>
      <div className="min-h-screen bg-gray-50 flex flex-col">
        <Nav />
        <main className="flex-1 p-6">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/projects/:projectId" element={<ProjectView />} />
            <Route path="/projects/:projectId/stories/:storyId" element={<StoryEditor />} />
            <Route path="/projects/:projectId/stories/new" element={<StoryEditor />} />
            <Route path="/prd" element={<PrdGenerator />} />
            <Route path="/runs" element={<AgentRuns />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}

export default function App() {
  return (
    <KeycloakProvider>
      <AuthenticatedApp />
    </KeycloakProvider>
  );
}
