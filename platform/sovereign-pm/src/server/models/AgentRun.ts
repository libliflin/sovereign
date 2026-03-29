import { DataTypes, Model, Optional } from 'sequelize';
import sequelize from '../database';

export type RunStatus = 'running' | 'pass' | 'fail';

interface AgentRunAttributes {
  id: string;
  storyId: string;
  status: RunStatus;
  logs: string;
  startedAt: Date;
  completedAt: Date | null;
  createdAt?: Date;
  updatedAt?: Date;
}

type AgentRunCreationAttributes = Optional<AgentRunAttributes, 'id' | 'completedAt'>;

class AgentRun
  extends Model<AgentRunAttributes, AgentRunCreationAttributes>
  implements AgentRunAttributes
{
  public id!: string;
  public storyId!: string;
  public status!: RunStatus;
  public logs!: string;
  public startedAt!: Date;
  public completedAt!: Date | null;
  public readonly createdAt!: Date;
  public readonly updatedAt!: Date;
}

AgentRun.init(
  {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true,
    },
    storyId: {
      type: DataTypes.UUID,
      allowNull: false,
    },
    status: {
      type: DataTypes.ENUM('running', 'pass', 'fail'),
      allowNull: false,
      defaultValue: 'running',
    },
    logs: {
      type: DataTypes.TEXT,
      allowNull: false,
      defaultValue: '',
    },
    startedAt: {
      type: DataTypes.DATE,
      allowNull: false,
      defaultValue: DataTypes.NOW,
    },
    completedAt: {
      type: DataTypes.DATE,
      allowNull: true,
    },
  },
  {
    sequelize,
    tableName: 'agent_runs',
    modelName: 'AgentRun',
  }
);

export default AgentRun;
