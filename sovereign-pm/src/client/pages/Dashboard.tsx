import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { getProjects, createProject, Project } from '../api/client';

export default function Dashboard() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [newName, setNewName] = useState('');
  const [newDesc, setNewDesc] = useState('');
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    getProjects()
      .then(setProjects)
      .finally(() => setLoading(false));
  }, []);

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    if (!newName.trim()) return;
    setCreating(true);
    try {
      const p = await createProject({ name: newName.trim(), description: newDesc.trim() });
      setProjects((prev) => [p, ...prev]);
      setNewName('');
      setNewDesc('');
    } finally {
      setCreating(false);
    }
  }

  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">Projects</h1>

      <form onSubmit={handleCreate} className="mb-8 bg-white p-4 rounded shadow flex gap-3 items-end">
        <div className="flex-1">
          <label className="block text-sm font-medium mb-1">Project name</label>
          <input
            className="w-full border rounded px-3 py-2 text-sm"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="Sovereign Platform"
          />
        </div>
        <div className="flex-1">
          <label className="block text-sm font-medium mb-1">Description</label>
          <input
            className="w-full border rounded px-3 py-2 text-sm"
            value={newDesc}
            onChange={(e) => setNewDesc(e.target.value)}
            placeholder="Optional"
          />
        </div>
        <button
          type="submit"
          disabled={creating || !newName.trim()}
          className="bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700 disabled:opacity-50"
        >
          {creating ? 'Creating…' : 'New Project'}
        </button>
      </form>

      {loading ? (
        <p className="text-gray-500">Loading…</p>
      ) : projects.length === 0 ? (
        <p className="text-gray-500">No projects yet. Create one above.</p>
      ) : (
        <div className="grid gap-4">
          {projects.map((p) => (
            <Link
              key={p.id}
              to={`/projects/${p.id}`}
              className="block bg-white p-4 rounded shadow hover:shadow-md transition"
            >
              <h2 className="font-semibold text-lg">{p.name}</h2>
              {p.description && <p className="text-gray-600 text-sm mt-1">{p.description}</p>}
              <p className="text-xs text-gray-400 mt-2">{new Date(p.createdAt).toLocaleDateString()}</p>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
