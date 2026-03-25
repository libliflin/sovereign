import { buildRalphJobSpec } from '../routes/ralph';

describe('buildRalphJobSpec', () => {
  it('returns a valid K8s Job manifest', () => {
    const spec = buildRalphJobSpec('test-run-id', 10);

    expect(spec.apiVersion).toBe('batch/v1');
    expect(spec.kind).toBe('Job');
    expect(spec.metadata.name).toContain('ralph-run-test-run-id');
    expect(spec.metadata.namespace).toBe('sovereign-pm');
  });

  it('includes correct image and command', () => {
    const spec = buildRalphJobSpec('abc123', 5);
    const container = spec.spec.template.spec.containers[0];

    expect(container.image).toContain('sovereign-pm');
    expect(container.command).toContain('/app/scripts/ralph/ralph.sh');
    expect(container.args).toEqual(['--tool', 'claude', '5']);
  });

  it('includes resource requests and limits on the container', () => {
    const spec = buildRalphJobSpec('res-check', 3);
    const container = spec.spec.template.spec.containers[0];

    expect(container.resources.requests.cpu).toBeDefined();
    expect(container.resources.requests.memory).toBeDefined();
    expect(container.resources.limits.cpu).toBeDefined();
    expect(container.resources.limits.memory).toBeDefined();
  });

  it('mounts the prd volume', () => {
    const spec = buildRalphJobSpec('vol-check', 1);
    const volumeMount = spec.spec.template.spec.containers[0].volumeMounts[0];

    expect(volumeMount.mountPath).toBe('/app/prd');
  });
});
