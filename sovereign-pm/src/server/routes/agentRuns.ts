import { Router, Request, Response } from 'express';
import { AgentRun } from '../models';

const router = Router();

// GET /api/agent-runs
router.get('/', async (_req: Request, res: Response) => {
  const runs = await AgentRun.findAll({ order: [['startedAt', 'DESC']] });
  res.json(runs);
});

// GET /api/agent-runs/:id
router.get('/:id', async (req: Request, res: Response) => {
  const run = await AgentRun.findByPk(req.params.id);
  if (!run) {
    res.status(404).json({ error: 'AgentRun not found' });
    return;
  }
  res.json(run);
});

// POST /api/agent-runs
router.post('/', async (req: Request, res: Response) => {
  const { storyId, logs, startedAt } = req.body as {
    storyId: string;
    logs?: string;
    startedAt?: string;
  };
  if (!storyId) {
    res.status(400).json({ error: 'storyId is required' });
    return;
  }
  const run = await AgentRun.create({
    storyId,
    status: 'running',
    logs: logs || '',
    startedAt: startedAt ? new Date(startedAt) : new Date(),
    completedAt: null,
  });
  res.status(201).json(run);
});

// PUT /api/agent-runs/:id
router.put('/:id', async (req: Request, res: Response) => {
  const run = await AgentRun.findByPk(req.params.id);
  if (!run) {
    res.status(404).json({ error: 'AgentRun not found' });
    return;
  }
  const { status, logs, completedAt } = req.body as {
    status?: 'running' | 'pass' | 'fail';
    logs?: string;
    completedAt?: string;
  };
  await run.update({
    status: status ?? run.status,
    logs: logs ?? run.logs,
    completedAt: completedAt ? new Date(completedAt) : run.completedAt,
  });
  res.json(run);
});

export default router;
