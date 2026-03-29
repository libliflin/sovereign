import React, { useEffect, useState } from 'react';
import { generatePrd, getEpics, Epic, PrdDocument } from '../api/client';

export default function PrdGenerator() {
  const [epics, setEpics] = useState<Epic[]>([]);
  const [selectedEpicId, setSelectedEpicId] = useState<string>('');
  const [prd, setPrd] = useState<PrdDocument | null>(null);
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getEpics().then(setEpics);
  }, []);

  async function handleGenerate() {
    setLoading(true);
    setError(null);
    setPrd(null);
    try {
      const doc = await generatePrd(selectedEpicId || undefined);
      setPrd(doc);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to generate PRD');
    } finally {
      setLoading(false);
    }
  }

  async function handleCopy() {
    if (!prd) return;
    const text = JSON.stringify(prd, null, 2);
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback for environments without clipboard API
      const el = document.createElement('textarea');
      el.value = text;
      document.body.appendChild(el);
      el.select();
      document.execCommand('copy');
      document.body.removeChild(el);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }

  const prdJson = prd ? JSON.stringify(prd, null, 2) : '';

  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">PRD Generator</h1>
      <p className="text-gray-600 text-sm mb-4">
        Generate a <code className="bg-gray-100 px-1 rounded">prd.json</code> compatible with the Ralph agent loop.
        Select an epic to scope, or leave blank for all stories.
      </p>

      <div className="bg-white rounded shadow p-4 mb-6 flex gap-4 items-end">
        <div className="flex-1">
          <label className="block text-sm font-medium mb-1">Epic (optional)</label>
          <select
            className="w-full border rounded px-3 py-2 text-sm"
            value={selectedEpicId}
            onChange={(e) => setSelectedEpicId(e.target.value)}
          >
            <option value="">All stories</option>
            {epics.map((ep) => (
              <option key={ep.id} value={ep.id}>{ep.title}</option>
            ))}
          </select>
        </div>
        <button
          onClick={handleGenerate}
          disabled={loading}
          className="bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? 'Generating…' : 'Generate PRD'}
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded p-3 mb-4 text-sm">
          {error}
        </div>
      )}

      {prd && (
        <div className="bg-white rounded shadow">
          <div className="flex items-center justify-between px-4 py-3 border-b">
            <div className="text-sm font-medium">
              Generated PRD — {prd.stories.length} {prd.stories.length === 1 ? 'story' : 'stories'}
            </div>
            <button
              onClick={handleCopy}
              className="text-sm bg-gray-100 px-3 py-1 rounded hover:bg-gray-200 transition"
            >
              {copied ? '✓ Copied!' : 'Copy JSON'}
            </button>
          </div>
          <pre className="text-xs font-mono p-4 overflow-auto max-h-[500px] bg-gray-50 rounded-b">
            {prdJson}
          </pre>
        </div>
      )}
    </div>
  );
}
