import sequelize from './database';
import { Project, Epic, Story, AgentRun } from './models';
import app from './app';

const PORT = parseInt(process.env.PORT || '3000', 10);

async function start(): Promise<void> {
  // Sync all models (alter: false in production, true in development)
  await sequelize.sync({ alter: process.env.NODE_ENV === 'development' });
  console.log('Database synced');

  // Reference models to ensure they are registered
  void Project;
  void Epic;
  void Story;
  void AgentRun;

  app.listen(PORT, () => {
    console.log(`Sovereign PM API listening on port ${PORT}`);
  });
}

start().catch((err: unknown) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
