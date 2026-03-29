import React, { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { getEpics, getStories, Epic, Story } from '../api/client';

export default function ProjectView() {
  const { projectId } = useParams<{ projectId: string }>();
  const [epics, setEpics] = useState<Epic[]>([]);
  const [stories, setStories] = useState<Story[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([getEpics(), getStories()])
      .then(([allEpics, allStories]) => {
        setEpics(allEpics.filter((e) => e.projectId === projectId));
        setStories(allStories);
      })
      .finally(() => setLoading(false));
  }, [projectId]);

  const storiesForEpic = (epicId: string) => stories.filter((s) => s.epicId === epicId);

  if (loading) return <div className="text-gray-500">Loading…</div>;

  return (
    <div className="max-w-5xl mx-auto">
      <div className="flex items-center gap-3 mb-6">
        <Link to="/" className="text-blue-600 hover:underline text-sm">← Projects</Link>
        <h1 className="text-2xl font-bold">Epic Kanban</h1>
      </div>

      {epics.length === 0 ? (
        <p className="text-gray-500">No epics found for this project.</p>
      ) : (
        <div className="flex gap-4 overflow-x-auto pb-4">
          {epics.map((epic) => (
            <div key={epic.id} className="min-w-64 bg-white rounded shadow p-4 flex flex-col gap-3">
              <h2 className="font-semibold text-base border-b pb-2">{epic.title}</h2>
              {storiesForEpic(epic.id).length === 0 ? (
                <p className="text-xs text-gray-400">No stories</p>
              ) : (
                storiesForEpic(epic.id).map((story) => (
                  <Link
                    key={story.id}
                    to={`/projects/${projectId}/stories/${story.id}`}
                    className={`block p-2 rounded border text-sm hover:bg-gray-50 ${
                      story.passes ? 'border-green-300 bg-green-50' : 'border-gray-200'
                    }`}
                  >
                    <div className="font-medium">{story.title}</div>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="text-xs text-gray-400">{story.points}pt</span>
                      <span
                        className={`text-xs px-1.5 py-0.5 rounded ${
                          story.passes ? 'bg-green-100 text-green-700' : 'bg-yellow-100 text-yellow-700'
                        }`}
                      >
                        {story.passes ? 'Done' : 'Pending'}
                      </span>
                    </div>
                  </Link>
                ))
              )}
              <Link
                to={`/projects/${projectId}/stories/new`}
                className="text-xs text-blue-600 hover:underline mt-auto"
              >
                + Add story
              </Link>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
