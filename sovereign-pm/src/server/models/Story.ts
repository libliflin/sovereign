import { DataTypes, Model, Optional } from 'sequelize';
import sequelize from '../database';

interface StoryAttributes {
  id: string;
  epicId: string;
  title: string;
  description: string;
  acceptanceCriteria: string[];
  priority: number;
  sprintIncrement: number;
  branchName: string;
  passes: boolean;
  points: number;
  createdAt?: Date;
  updatedAt?: Date;
}

type StoryCreationAttributes = Optional<StoryAttributes, 'id'>;

class Story extends Model<StoryAttributes, StoryCreationAttributes> implements StoryAttributes {
  public id!: string;
  public epicId!: string;
  public title!: string;
  public description!: string;
  public acceptanceCriteria!: string[];
  public priority!: number;
  public sprintIncrement!: number;
  public branchName!: string;
  public passes!: boolean;
  public points!: number;
  public readonly createdAt!: Date;
  public readonly updatedAt!: Date;
}

Story.init(
  {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true,
    },
    epicId: {
      type: DataTypes.UUID,
      allowNull: false,
    },
    title: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    description: {
      type: DataTypes.TEXT,
      allowNull: false,
      defaultValue: '',
    },
    acceptanceCriteria: {
      type: DataTypes.JSON,
      allowNull: false,
      defaultValue: [],
    },
    priority: {
      type: DataTypes.INTEGER,
      allowNull: false,
      defaultValue: 1,
    },
    sprintIncrement: {
      type: DataTypes.INTEGER,
      field: 'sprint_increment',
      allowNull: false,
      defaultValue: 1,
    },
    branchName: {
      type: DataTypes.STRING,
      allowNull: false,
      defaultValue: '',
    },
    passes: {
      type: DataTypes.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    },
    points: {
      type: DataTypes.INTEGER,
      allowNull: false,
      defaultValue: 1,
    },
  },
  {
    sequelize,
    tableName: 'stories',
    modelName: 'Story',
  }
);

export default Story;
