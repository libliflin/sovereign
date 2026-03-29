import { expressjwt } from 'express-jwt';
import jwksRsa from 'jwks-rsa';
import { Request, Response, NextFunction } from 'express';

const KEYCLOAK_URL = process.env.KEYCLOAK_URL || 'http://keycloak:8080';
const KEYCLOAK_REALM = process.env.KEYCLOAK_REALM || 'sovereign';

// In test mode, allow HS256 tokens signed with JWT_TEST_SECRET for route testing.
// In production, validate RS256 tokens from Keycloak JWKS endpoint.
const TEST_SECRET = process.env.JWT_TEST_SECRET;

const jwtMiddleware = TEST_SECRET
  ? expressjwt({ secret: TEST_SECRET, algorithms: ['HS256'] })
  : expressjwt({
      secret: jwksRsa.expressJwtSecret({
        cache: true,
        rateLimit: true,
        jwksRequestsPerMinute: 5,
        jwksUri: `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/certs`,
      }) as Parameters<typeof expressjwt>[0]['secret'],
      algorithms: ['RS256'],
      issuer: `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}`,
    });

export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  jwtMiddleware(req, res, (err) => {
    if (err) {
      res.status(401).json({ error: 'Unauthorized', message: err.message });
      return;
    }
    next();
  });
}
