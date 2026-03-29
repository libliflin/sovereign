import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import Keycloak from 'keycloak-js';
import keycloak from './keycloak';

interface KeycloakContextValue {
  keycloak: Keycloak;
  initialized: boolean;
  authenticated: boolean;
  token: string | undefined;
}

const KeycloakContext = createContext<KeycloakContextValue | null>(null);

export function KeycloakProvider({ children }: { children: ReactNode }) {
  const [initialized, setInitialized] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    keycloak
      .init({ onLoad: 'login-required', pkceMethod: 'S256' })
      .then((auth) => {
        setAuthenticated(auth);
        setInitialized(true);
      })
      .catch(() => {
        setInitialized(true);
      });
  }, []);

  return (
    <KeycloakContext.Provider
      value={{
        keycloak,
        initialized,
        authenticated,
        token: keycloak.token,
      }}
    >
      {children}
    </KeycloakContext.Provider>
  );
}

export function useKeycloak(): KeycloakContextValue {
  const ctx = useContext(KeycloakContext);
  if (!ctx) throw new Error('useKeycloak must be used inside KeycloakProvider');
  return ctx;
}
