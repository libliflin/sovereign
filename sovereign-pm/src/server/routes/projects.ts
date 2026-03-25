import { Router, Request, Response } from 'express';
import { Project } from '../models';

const router = Router();

// GET /api/projects
router.get('/', async (_req: Request, res: Response) => {
  const projects = await Project.findAll({ order: [['createdAt', 'DESC']] });
  res.json(projects);
});

// GET /api/projects/:id
router.get('/:id', async (req: Request, res: Response) => {
  const project = await Project.findByPk(req.params.id);
  if (!project) {
    res.status(404).json({ error: 'Project not found' });
    return;
  }
  res.json(project);
});

// POST /api/projects
router.post('/', async (req: Request, res: Response) => {
  const { name, description } = req.body as { name: string; description: string };
  if (!name) {
    res.status(400).json({ error: 'name is required' });
    return;
  }
  const project = await Project.create({ name, description: description || '' });
  res.status(201).json(project);
});

// PUT /api/projects/:id
router.put('/:id', async (req: Request, res: Response) => {
  const project = await Project.findByPk(req.params.id);
  if (!project) {
    res.status(404).json({ error: 'Project not found' });
    return;
  }
  const { name, description } = req.body as { name?: string; description?: string };
  await project.update({ name: name ?? project.name, description: description ?? project.description });
  res.json(project);
});

// DELETE /api/projects/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const project = await Project.findByPk(req.params.id);
  if (!project) {
    res.status(404).json({ error: 'Project not found' });
    return;
  }
  await project.destroy();
  res.status(204).send();
});

export default router;
