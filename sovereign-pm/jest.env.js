// Sets environment variables BEFORE any module is imported.
// This ensures database.ts picks up sqlite dialect for all tests.
process.env.DATABASE_DIALECT = 'sqlite';
process.env.DATABASE_URL = ':memory:';
process.env.JWT_TEST_SECRET = 'sovereign-test-secret-32-chars-ok';
process.env.NODE_ENV = 'test';
