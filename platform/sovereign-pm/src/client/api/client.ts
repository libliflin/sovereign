import keycloak from '../keycloak';

async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  // Refresh token if it expires in < 30s
  if (keycloak.token) {
    await keycloak.updateToken(30).catch(() => keycloak.logout());
  }

  const res = await fetch(`/api${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${keycloak.token ?? ''}`,
      ...options.headers,
    },
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API ${res.status}: ${text}`);
  }

  if (res.status === 204) return undefined as unknown as T;
  return res.json() as Promise<T>;
}

export interface Project {
  id: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
}

export interface Epic {
  id: string;
  projectId: string;
  title: string;
  description: string;
  priority: number;
  createdAt: string;
  updatedAt: string;
}

export interface Story {
  id: string;
  epicId: string;
  title: string;
  description: string;
  acceptanceCriteria: string[];
  priority: number;
  sprintIncrement: number;
  branchName: string;
  passes: boolean;
  points: number;
  createdAt: string;
  updatedAt: string;
}

export interface AgentRun {
  id: string;
  storyId: string;
  status: 'running' | 'pass' | 'fail';
  logs: string;
  startedAt: string;
  completedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface PrdDocument {
  branchName: string;
  stories: Array<{
    id: string;
    title: string;
    description: string;
    acceptanceCriteria: string[];
    increment: number;
    priority: number;
    passes: boolean;
    branchName: string;
    points: number;
  }>;
}

// Projects
export const getProjects = () => apiFetch<Project[]>('/projects');
export const createProject = (data: { name: string; description: string }) =>
  apiFetch<Project>('/projects', { method: 'POST', body: JSON.stringify(data) });

// Epics
export const getEpics = () => apiFetch<Epic[]>('/epics');
export const createEpic = (data: { projectId: string; title: string; description?: string; priority?: number }) =>
  apiFetch<Epic>('/epics', { method: 'POST', body: JSON.stringify(data) });
export const updateEpic = (id: string, data: Partial<Epic>) =>
  apiFetch<Epic>(`/epics/${id}`, { method: 'PUT', body: JSON.stringify(data) });

// Stories
export const getStories = () => apiFetch<Story[]>('/stories');
export const getStory = (id: string) => apiFetch<Story>(`/stories/${id}`);
export const createStory = (data: Partial<Story> & { epicId: string; title: string }) =>
  apiFetch<Story>('/stories', { method: 'POST', body: JSON.stringify(data) });
export const updateStory = (id: string, data: Partial<Story>) =>
  apiFetch<Story>(`/stories/${id}`, { method: 'PUT', body: JSON.stringify(data) });
export const deleteStory = (id: string) => apiFetch<void>(`/stories/${id}`, { method: 'DELETE' });

// AgentRuns
export const getAgentRuns = () => apiFetch<AgentRun[]>('/agent-runs');
export const getRalphRuns = () => apiFetch<AgentRun[]>('/ralph/runs');

// PRD
export const generatePrd = (epicId?: string) =>
  apiFetch<PrdDocument>('/prd/generate', { method: 'POST', body: JSON.stringify({ epicId }) });

// Ralph trigger
export const triggerRalph = (storyId: string, iterations?: number) =>
  apiFetch<{ runId: string; message: string; jobSpec: unknown }>('/ralph/trigger', {
    method: 'POST',
    body: JSON.stringify({ storyId, iterations }),
  });
