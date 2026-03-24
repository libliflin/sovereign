# SonarQube + GitLab CI Integration

## Overview

SonarQube is deployed at `https://sonar.<domain>` and secured with Keycloak OIDC.
GitLab CI pipelines publish scan results automatically on each push.

## Prerequisites

1. SonarQube is running (`kubectl get pods -n sonarqube`)
2. A SonarQube project token has been generated (Settings → Security → Tokens)
3. GitLab CI runner is available

## GitLab CI Configuration

### 1. Store the token as a GitLab CI variable

In your GitLab project: **Settings → CI/CD → Variables**

| Variable | Value |
|---|---|
| `SONAR_HOST_URL` | `https://sonar.<domain>` |
| `SONAR_TOKEN` | `<token from SonarQube>` |

Mark `SONAR_TOKEN` as **masked** and **protected**.

### 2. Add the SonarQube scan to `.gitlab-ci.yml`

```yaml
sonarqube-scan:
  stage: test
  image:
    name: sonarsource/sonar-scanner-cli:latest
    entrypoint: [""]
  variables:
    SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
    GIT_DEPTH: "0"
  cache:
    key: "${CI_JOB_NAME}"
    paths:
      - .sonar/cache
  script:
    - sonar-scanner
      -Dsonar.projectKey=${CI_PROJECT_NAME}
      -Dsonar.sources=.
      -Dsonar.host.url=${SONAR_HOST_URL}
      -Dsonar.token=${SONAR_TOKEN}
  allow_failure: true
  only:
    - main
    - merge_requests
```

### 3. sonar-project.properties (optional)

Add a `sonar-project.properties` file to your project root to set per-project configuration:

```properties
sonar.projectKey=my-project
sonar.sources=src
sonar.tests=test
sonar.language=js
sonar.javascript.lcov.reportPaths=coverage/lcov.info
```

## Quality Gate enforcement

To block merges when the Quality Gate fails, enable **SonarQube → Project Settings → Quality Gate → Enforce**.
GitLab CI will see a non-zero exit from `sonar-scanner` and fail the pipeline.

## Keycloak OIDC login

Users access SonarQube at `https://sonar.<domain>`. The "Log in with Keycloak" button
appears automatically once `sonar.auth.oidc.enabled=true` is set (configured in the Helm chart).

Keycloak client: `sovereign-sonarqube` in realm `sovereign`.
Create the client secret as a Sealed Secret named `sonarqube-oidc-secret` with key `client-secret`.
