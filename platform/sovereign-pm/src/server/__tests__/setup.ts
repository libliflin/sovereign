import sequelize from '../database';
import '../models'; // register all models and associations

// Use SQLite in-memory for tests
process.env.DATABASE_DIALECT = 'sqlite';
process.env.DATABASE_URL = ':memory:';
// Use HS256 test secret so JWT middleware works without Keycloak
process.env.JWT_TEST_SECRET = 'sovereign-test-secret-32-chars-ok';

beforeAll(async () => {
  await sequelize.sync({ force: true });
});

afterAll(async () => {
  await sequelize.close();
});
