import { Router, Request, Response } from 'express';
import { Epic } from '../models';

const router = Router();

// GET /api/epics
router.get('/', async (_req: Request, res: Response) => {
  const epics = await Epic.findAll({ order: [['priority', 'ASC']] });
  res.json(epics);
});

// GET /api/epics/:id
router.get('/:id', async (req: Request, res: Response) => {
  const epic = await Epic.findByPk(req.params.id);
  if (!epic) {
    res.status(404).json({ error: 'Epic not found' });
    return;
  }
  res.json(epic);
});

// POST /api/epics
router.post('/', async (req: Request, res: Response) => {
  const { projectId, title, description, priority } = req.body as {
    projectId: string;
    title: string;
    description?: string;
    priority?: number;
  };
  if (!projectId || !title) {
    res.status(400).json({ error: 'projectId and title are required' });
    return;
  }
  const epic = await Epic.create({
    projectId,
    title,
    description: description || '',
    priority: priority ?? 1,
  });
  res.status(201).json(epic);
});

// PUT /api/epics/:id
router.put('/:id', async (req: Request, res: Response) => {
  const epic = await Epic.findByPk(req.params.id);
  if (!epic) {
    res.status(404).json({ error: 'Epic not found' });
    return;
  }
  const { title, description, priority } = req.body as {
    title?: string;
    description?: string;
    priority?: number;
  };
  await epic.update({
    title: title ?? epic.title,
    description: description ?? epic.description,
    priority: priority ?? epic.priority,
  });
  res.json(epic);
});

// DELETE /api/epics/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const epic = await Epic.findByPk(req.params.id);
  if (!epic) {
    res.status(404).json({ error: 'Epic not found' });
    return;
  }
  await epic.destroy();
  res.status(204).send();
});

export default router;
