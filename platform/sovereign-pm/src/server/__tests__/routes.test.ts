import request from 'supertest';
import jwt from 'jsonwebtoken';
import sequelize from '../database';
import '../models'; // register all models + associations
import app from '../app';

const TEST_SECRET = process.env.JWT_TEST_SECRET as string;

function makeToken(payload: object = { sub: 'test-user', name: 'Test User' }): string {
  return jwt.sign(payload, TEST_SECRET, { algorithm: 'HS256', expiresIn: '1h' });
}

const authHeader = () => ({ Authorization: `Bearer ${makeToken()}` });

beforeAll(async () => {
  await sequelize.sync({ force: true });
});

afterAll(async () => {
  await sequelize.close();
});

// ── AUTH ──────────────────────────────────────────────────────────────────────

describe('Auth middleware', () => {
  it('returns 401 on unauthenticated request to /api/projects', async () => {
    const res = await request(app).get('/api/projects');
    expect(res.status).toBe(401);
  });

  it('returns 401 on unauthenticated request to /api/epics', async () => {
    const res = await request(app).get('/api/epics');
    expect(res.status).toBe(401);
  });

  it('returns 401 on unauthenticated request to /api/stories', async () => {
    const res = await request(app).get('/api/stories');
    expect(res.status).toBe(401);
  });

  it('returns 401 on unauthenticated request to /api/agent-runs', async () => {
    const res = await request(app).get('/api/agent-runs');
    expect(res.status).toBe(401);
  });

  it('allows unauthenticated access to /health', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
  });
});

// ── PROJECTS ──────────────────────────────────────────────────────────────────

describe('GET /api/projects', () => {
  it('returns empty array initially', async () => {
    const res = await request(app).get('/api/projects').set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});

describe('POST /api/projects', () => {
  it('creates a project', async () => {
    const res = await request(app)
      .post('/api/projects')
      .set(authHeader())
      .send({ name: 'Sovereign Platform', description: 'Test project' });
    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Sovereign Platform');
    expect(res.body.id).toBeDefined();
  });

  it('returns 400 when name is missing', async () => {
    const res = await request(app).post('/api/projects').set(authHeader()).send({});
    expect(res.status).toBe(400);
  });
});

// ── EPICS ─────────────────────────────────────────────────────────────────────

let projectId: string;
let epicId: string;

describe('POST /api/epics', () => {
  beforeAll(async () => {
    const res = await request(app)
      .post('/api/projects')
      .set(authHeader())
      .send({ name: 'Epic Test Project', description: '' });
    projectId = res.body.id as string;
  });

  it('creates an epic', async () => {
    const res = await request(app)
      .post('/api/epics')
      .set(authHeader())
      .send({ projectId, title: 'E1: Bootstrap', description: 'Bootstrap the cluster', priority: 1 });
    expect(res.status).toBe(201);
    expect(res.body.title).toBe('E1: Bootstrap');
    epicId = res.body.id as string;
  });

  it('returns 400 when projectId is missing', async () => {
    const res = await request(app)
      .post('/api/epics')
      .set(authHeader())
      .send({ title: 'No project' });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/epics', () => {
  it('returns list of epics', async () => {
    const res = await request(app).get('/api/epics').set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
  });
});

// ── STORIES ───────────────────────────────────────────────────────────────────

let storyId: string;

describe('POST /api/stories', () => {
  it('creates a story', async () => {
    const res = await request(app)
      .post('/api/stories')
      .set(authHeader())
      .send({
        epicId,
        title: 'Install Cilium',
        description: 'Deploy Cilium CNI to the cluster',
        acceptanceCriteria: ['helm lint passes', 'pods Running'],
        priority: 1,
        increment: 1,
        branchName: 'feature/cilium',
        points: 2,
      });
    expect(res.status).toBe(201);
    expect(res.body.title).toBe('Install Cilium');
    expect(res.body.passes).toBe(false);
    storyId = res.body.id as string;
  });

  it('returns 400 when epicId is missing', async () => {
    const res = await request(app)
      .post('/api/stories')
      .set(authHeader())
      .send({ title: 'No epic' });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/stories', () => {
  it('returns list of stories', async () => {
    const res = await request(app).get('/api/stories').set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
  });
});

// ── AGENT RUNS ────────────────────────────────────────────────────────────────

describe('POST /api/agent-runs', () => {
  it('creates an agent run', async () => {
    const res = await request(app)
      .post('/api/agent-runs')
      .set(authHeader())
      .send({ storyId });
    expect(res.status).toBe(201);
    expect(res.body.status).toBe('running');
    expect(res.body.storyId).toBe(storyId);
  });

  it('returns 400 when storyId is missing', async () => {
    const res = await request(app).post('/api/agent-runs').set(authHeader()).send({});
    expect(res.status).toBe(400);
  });
});

describe('GET /api/agent-runs', () => {
  it('returns list of agent runs', async () => {
    const res = await request(app).get('/api/agent-runs').set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
  });
});

// ── PRD GENERATE ──────────────────────────────────────────────────────────────

describe('POST /api/prd/generate', () => {
  it('returns PRD document matching prd.json schema', async () => {
    const res = await request(app)
      .post('/api/prd/generate')
      .set(authHeader())
      .send({ epicId });
    expect(res.status).toBe(200);

    // Verify prd.json schema shape
    const prd = res.body as {
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
    };
    expect(typeof prd.branchName).toBe('string');
    expect(Array.isArray(prd.stories)).toBe(true);
    expect(prd.stories.length).toBeGreaterThan(0);

    const story = prd.stories[0];
    expect(typeof story.id).toBe('string');
    expect(typeof story.title).toBe('string');
    expect(typeof story.description).toBe('string');
    expect(Array.isArray(story.acceptanceCriteria)).toBe(true);
    expect(typeof story.increment).toBe('number');
    expect(typeof story.priority).toBe('number');
    expect(typeof story.passes).toBe('boolean');
    expect(typeof story.branchName).toBe('string');
    expect(typeof story.points).toBe('number');
  });

  it('returns 404 when no stories found', async () => {
    const res = await request(app)
      .post('/api/prd/generate')
      .set(authHeader())
      .send({ epicId: '00000000-0000-0000-0000-000000000000' });
    expect(res.status).toBe(404);
  });
});

// ── RALPH TRIGGER ─────────────────────────────────────────────────────────────

describe('POST /api/ralph/trigger', () => {
  it('returns 202 with jobSpec containing correct image and command', async () => {
    const res = await request(app)
      .post('/api/ralph/trigger')
      .set(authHeader())
      .send({ storyId, iterations: 5 });
    expect(res.status).toBe(202);
    expect(res.body.runId).toBeDefined();
    expect(res.body.message).toBe('Ralph job queued');

    const jobSpec = res.body.jobSpec as {
      kind: string;
      spec: {
        template: {
          spec: {
            containers: Array<{ image: string; command: string[]; args: string[] }>;
          };
        };
      };
    };

    // Verify K8s Job spec structure
    expect(jobSpec.kind).toBe('Job');

    const container = jobSpec.spec.template.spec.containers[0];
    expect(container.image).toContain('sovereign-pm');
    expect(container.command).toContain('/app/scripts/ralph/ralph.sh');
    expect(container.args).toContain('--tool');
    expect(container.args).toContain('claude');
    expect(container.args).toContain('5');
  });

  it('returns 400 when storyId is missing', async () => {
    const res = await request(app).post('/api/ralph/trigger').set(authHeader()).send({});
    expect(res.status).toBe(400);
  });
});

describe('GET /api/ralph/runs', () => {
  it('returns list of runs', async () => {
    const res = await request(app).get('/api/ralph/runs').set(authHeader());
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});
