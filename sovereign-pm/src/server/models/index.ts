import Project from './Project';
import Epic from './Epic';
import Story from './Story';
import AgentRun from './AgentRun';

// Associations
Epic.belongsTo(Project, { foreignKey: 'projectId', as: 'project' });
Project.hasMany(Epic, { foreignKey: 'projectId', as: 'epics' });

Story.belongsTo(Epic, { foreignKey: 'epicId', as: 'epic' });
Epic.hasMany(Story, { foreignKey: 'epicId', as: 'stories' });

AgentRun.belongsTo(Story, { foreignKey: 'storyId', as: 'story' });
Story.hasMany(AgentRun, { foreignKey: 'storyId', as: 'agentRuns' });

export { Project, Epic, Story, AgentRun };
