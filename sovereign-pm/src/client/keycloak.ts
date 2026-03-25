import Keycloak from 'keycloak-js';

const keycloakUrl = import.meta.env.VITE_KEYCLOAK_URL as string | undefined ?? 'http://keycloak:8080';
const keycloakRealm = import.meta.env.VITE_KEYCLOAK_REALM as string | undefined ?? 'sovereign';
const keycloakClientId = import.meta.env.VITE_KEYCLOAK_CLIENT_ID as string | undefined ?? 'sovereign-pm';

const keycloak = new Keycloak({
  url: keycloakUrl,
  realm: keycloakRealm,
  clientId: keycloakClientId,
});

export default keycloak;
