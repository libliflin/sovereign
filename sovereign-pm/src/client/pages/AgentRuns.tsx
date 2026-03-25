import React, { useEffect, useState } from 'react';
import { getRalphRuns, AgentRun } from '../api/client';

const STATUS_STYLES: Record<AgentRun['status'], string> = {
  running: 'bg-blue-100 text-blue-700',
  pass: 'bg-green-100 text-green-700',
  fail: 'bg-red-100 text-red-700',
};

const STATUS_LABEL: Record<AgentRun['status'], string> = {
  running: 'Running',
  pass: 'Pass',
  fail: 'Fail',
};

export default function AgentRuns() {
  const [runs, setRuns] = useState<AgentRun[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedRunId, setExpandedRunId] = useState<string | null>(null);

  useEffect(() => {
    getRalphRuns()
      .then(setRuns)
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="text-gray-500">Loading…</div>;

  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">Agent Run History</h1>
      <p className="text-gray-600 text-sm mb-4">
        History of Ralph agent loop runs. Each run is associated with a story and shows pass/fail status.
      </p>

      {runs.length === 0 ? (
        <div className="bg-white rounded shadow p-6 text-gray-500 text-center">
          No agent runs yet. Trigger a run from the Story Editor.
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {runs.map((run) => (
            <div key={run.id} className="bg-white rounded shadow overflow-hidden">
              <div
                className="flex items-center gap-4 px-4 py-3 cursor-pointer hover:bg-gray-50"
                onClick={() => setExpandedRunId(expandedRunId === run.id ? null : run.id)}
              >
                <span
                  className={`text-xs font-medium px-2 py-0.5 rounded-full ${STATUS_STYLES[run.status]}`}
                >
                  {STATUS_LABEL[run.status]}
                </span>
                <span className="text-sm font-mono text-gray-600 truncate flex-1">
                  Run {run.id.slice(0, 8)}…
                </span>
                <span className="text-xs text-gray-400">
                  Story: {run.storyId.slice(0, 8)}…
                </span>
                <span className="text-xs text-gray-400">
                  {new Date(run.startedAt).toLocaleString()}
                </span>
                {run.completedAt && (
                  <span className="text-xs text-gray-400">
                    → {new Date(run.completedAt).toLocaleString()}
                  </span>
                )}
                <span className="text-gray-400 text-sm">{expandedRunId === run.id ? '▲' : '▼'}</span>
              </div>

              {expandedRunId === run.id && (
                <div className="border-t bg-gray-900 text-green-400 font-mono text-xs p-4 max-h-64 overflow-auto whitespace-pre-wrap">
                  {run.logs || '(no logs)'}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
