import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { getStory, createStory, updateStory, getEpics, Epic, Story } from '../api/client';

export default function StoryEditor() {
  const { projectId, storyId } = useParams<{ projectId: string; storyId?: string }>();
  const navigate = useNavigate();
  const isNew = storyId === undefined || storyId === 'new';

  const [epics, setEpics] = useState<Epic[]>([]);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [epicId, setEpicId] = useState('');
  const [acceptanceCriteria, setAcceptanceCriteria] = useState('');
  const [priority, setPriority] = useState(1);
  const [increment, setIncrement] = useState(1);
  const [branchName, setBranchName] = useState('');
  const [points, setPoints] = useState(1);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    getEpics().then((all) => {
      const projectEpics = all.filter((e) => e.projectId === projectId);
      setEpics(projectEpics);
      if (projectEpics.length > 0 && !epicId) setEpicId(projectEpics[0].id);
    });

    if (!isNew && storyId) {
      getStory(storyId).then((s: Story) => {
        setTitle(s.title);
        setDescription(s.description);
        setEpicId(s.epicId);
        setAcceptanceCriteria(s.acceptanceCriteria.join('\n'));
        setPriority(s.priority);
        setIncrement(s.sprintIncrement);
        setBranchName(s.branchName);
        setPoints(s.points);
      });
    }
  }, [projectId, storyId, isNew, epicId]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!epicId) return;
    setSaving(true);
    try {
      const data = {
        epicId,
        title,
        description,
        acceptanceCriteria: acceptanceCriteria.split('\n').filter(Boolean),
        priority,
        increment,
        branchName: branchName || `feature/${title.toLowerCase().replace(/\s+/g, '-')}`,
        points,
      };
      if (isNew) {
        await createStory(data);
      } else if (storyId) {
        await updateStory(storyId, data);
      }
      navigate(`/projects/${projectId}`);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="max-w-2xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">{isNew ? 'New Story' : 'Edit Story'}</h1>
      <form onSubmit={handleSubmit} className="bg-white rounded shadow p-6 flex flex-col gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Epic</label>
          <select
            className="w-full border rounded px-3 py-2 text-sm"
            value={epicId}
            onChange={(e) => setEpicId(e.target.value)}
            required
          >
            {epics.map((ep) => (
              <option key={ep.id} value={ep.id}>{ep.title}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Title</label>
          <input
            className="w-full border rounded px-3 py-2 text-sm"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Description</label>
          <textarea
            className="w-full border rounded px-3 py-2 text-sm"
            rows={4}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Acceptance Criteria (one per line)</label>
          <textarea
            className="w-full border rounded px-3 py-2 text-sm font-mono"
            rows={6}
            value={acceptanceCriteria}
            onChange={(e) => setAcceptanceCriteria(e.target.value)}
            placeholder="helm lint passes&#10;pods Running"
          />
        </div>

        <div className="grid grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium mb-1">Priority</label>
            <input
              type="number"
              className="w-full border rounded px-3 py-2 text-sm"
              min={1}
              value={priority}
              onChange={(e) => setPriority(Number(e.target.value))}
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Increment</label>
            <input
              type="number"
              className="w-full border rounded px-3 py-2 text-sm"
              min={1}
              value={increment}
              onChange={(e) => setIncrement(Number(e.target.value))}
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Points (1–5)</label>
            <input
              type="number"
              className="w-full border rounded px-3 py-2 text-sm"
              min={1}
              max={5}
              value={points}
              onChange={(e) => setPoints(Number(e.target.value))}
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Branch Name</label>
          <input
            className="w-full border rounded px-3 py-2 text-sm font-mono"
            value={branchName}
            onChange={(e) => setBranchName(e.target.value)}
            placeholder="feature/my-story"
          />
        </div>

        <div className="flex gap-3 justify-end">
          <button
            type="button"
            onClick={() => navigate(`/projects/${projectId}`)}
            className="px-4 py-2 text-sm border rounded hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saving}
            className="px-4 py-2 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {saving ? 'Saving…' : 'Save Story'}
          </button>
        </div>
      </form>
    </div>
  );
}
