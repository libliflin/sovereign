import { Sequelize } from 'sequelize';

const dialect = (process.env.DATABASE_DIALECT as 'postgres' | 'sqlite') || 'postgres';

let sequelize: Sequelize;

if (dialect === 'sqlite') {
  sequelize = new Sequelize({
    dialect: 'sqlite',
    storage: process.env.DATABASE_URL || ':memory:',
    logging: false,
  });
} else {
  sequelize = new Sequelize(
    process.env.DATABASE_URL || 'postgres://sovereign_pm:sovereign_pm@localhost:5432/sovereign_pm',
    {
      dialect: 'postgres',
      logging: process.env.NODE_ENV === 'development' ? console.log : false,
    }
  );
}

export default sequelize;
