import { Router, Request, Response } from 'express';
import { Story } from '../models';

const router = Router();

// GET /api/stories
router.get('/', async (_req: Request, res: Response) => {
  const stories = await Story.findAll({ order: [['priority', 'ASC']] });
  res.json(stories);
});

// GET /api/stories/:id
router.get('/:id', async (req: Request, res: Response) => {
  const story = await Story.findByPk(req.params.id);
  if (!story) {
    res.status(404).json({ error: 'Story not found' });
    return;
  }
  res.json(story);
});

// POST /api/stories
router.post('/', async (req: Request, res: Response) => {
  const { epicId, title, description, acceptanceCriteria, priority, increment, branchName, points } =
    req.body as {
      epicId: string;
      title: string;
      description?: string;
      acceptanceCriteria?: string[];
      priority?: number;
      increment?: number;
      branchName?: string;
      points?: number;
    };
  if (!epicId || !title) {
    res.status(400).json({ error: 'epicId and title are required' });
    return;
  }
  const story = await Story.create({
    epicId,
    title,
    description: description || '',
    acceptanceCriteria: acceptanceCriteria || [],
    priority: priority ?? 1,
    sprintIncrement: increment ?? 1,
    branchName: branchName || `feature/${title.toLowerCase().replace(/\s+/g, '-')}`,
    passes: false,
    points: points ?? 1,
  });
  res.status(201).json(story);
});

// PUT /api/stories/:id
router.put('/:id', async (req: Request, res: Response) => {
  const story = await Story.findByPk(req.params.id);
  if (!story) {
    res.status(404).json({ error: 'Story not found' });
    return;
  }
  const { title, description, acceptanceCriteria, priority, increment, branchName, passes, points } =
    req.body as {
      title?: string;
      description?: string;
      acceptanceCriteria?: string[];
      priority?: number;
      increment?: number;
      branchName?: string;
      passes?: boolean;
      points?: number;
    };
  await story.update({
    title: title ?? story.title,
    description: description ?? story.description,
    acceptanceCriteria: acceptanceCriteria ?? story.acceptanceCriteria,
    priority: priority ?? story.priority,
    sprintIncrement: increment ?? story.sprintIncrement,
    branchName: branchName ?? story.branchName,
    passes: passes ?? story.passes,
    points: points ?? story.points,
  });
  res.json(story);
});

// DELETE /api/stories/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const story = await Story.findByPk(req.params.id);
  if (!story) {
    res.status(404).json({ error: 'Story not found' });
    return;
  }
  await story.destroy();
  res.status(204).send();
});

export default router;
