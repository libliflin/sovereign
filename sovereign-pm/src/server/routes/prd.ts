import { Router, Request, Response } from 'express';
import { Story, Epic } from '../models';

const router = Router();

export interface PrdStory {
  id: string;
  title: string;
  description: string;
  acceptanceCriteria: string[];
  increment: number;
  priority: number;
  passes: boolean;
  branchName: string;
  points: number;
}

export interface PrdDocument {
  branchName: string;
  stories: PrdStory[];
}

// POST /api/prd/generate
// Accepts: { epicId?: string } to scope generation to an epic, or generates all pending stories
router.post('/generate', async (req: Request, res: Response) => {
  const { epicId } = req.body as { epicId?: string };

  const where = epicId ? { epicId } : {};
  const rawStories = await Story.findAll({
    where,
    include: [{ model: Epic, as: 'epic' }],
    order: [
      ['sprint_increment', 'ASC'],
      ['priority', 'ASC'],
    ],
  });

  if (rawStories.length === 0) {
    res.status(404).json({ error: 'No stories found' });
    return;
  }

  // Cast to typed Story instances
  const stories = rawStories as unknown as Story[];

  // Group by branchName — use the first story's branchName as the PRD branch
  const primaryBranch = stories[0].branchName || 'feature/generated-prd';

  const prd: PrdDocument = {
    branchName: primaryBranch,
    stories: stories.map((s) => ({
      id: s.id,
      title: s.title,
      description: s.description,
      acceptanceCriteria: s.acceptanceCriteria,
      increment: s.sprintIncrement,
      priority: s.priority,
      passes: s.passes,
      branchName: s.branchName,
      points: s.points,
    })),
  };

  res.json(prd);
});

export default router;
