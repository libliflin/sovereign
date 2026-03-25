import { DataTypes, Model, Optional } from 'sequelize';
import sequelize from '../database';

interface EpicAttributes {
  id: string;
  projectId: string;
  title: string;
  description: string;
  priority: number;
  createdAt?: Date;
  updatedAt?: Date;
}

type EpicCreationAttributes = Optional<EpicAttributes, 'id'>;

class Epic extends Model<EpicAttributes, EpicCreationAttributes> implements EpicAttributes {
  public id!: string;
  public projectId!: string;
  public title!: string;
  public description!: string;
  public priority!: number;
  public readonly createdAt!: Date;
  public readonly updatedAt!: Date;
}

Epic.init(
  {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true,
    },
    projectId: {
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
    priority: {
      type: DataTypes.INTEGER,
      allowNull: false,
      defaultValue: 1,
    },
  },
  {
    sequelize,
    tableName: 'epics',
    modelName: 'Epic',
  }
);

export default Epic;
