import express from 'express';
import { authMiddleware } from './middleware/auth';
import projectsRouter from './routes/projects';
import epicsRouter from './routes/epics';
import storiesRouter from './routes/stories';
import agentRunsRouter from './routes/agentRuns';
import prdRouter from './routes/prd';
import ralphRouter from './routes/ralph';

const app = express();

app.use(express.json());

// Health check — unauthenticated
app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

// All /api routes require authentication
app.use('/api', authMiddleware);

app.use('/api/projects', projectsRouter);
app.use('/api/epics', epicsRouter);
app.use('/api/stories', storiesRouter);
app.use('/api/agent-runs', agentRunsRouter);
app.use('/api/prd', prdRouter);
app.use('/api/ralph', ralphRouter);

export default app;
