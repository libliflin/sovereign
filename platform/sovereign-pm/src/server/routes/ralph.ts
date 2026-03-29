import { Router, Request, Response } from 'express';
import { AgentRun } from '../models';

const router = Router();

const SOVEREIGN_PM_IMAGE =
  process.env.SOVEREIGN_PM_IMAGE ||
  'harbor.sovereign-autarky.dev/sovereign/sovereign-pm:latest';
const NAMESPACE = process.env.RALPH_NAMESPACE || 'sovereign-pm';
const PVC_NAME = process.env.RALPH_PVC || 'sovereign-prd-pvc';

export interface RalphJobSpec {
  apiVersion: string;
  kind: string;
  metadata: {
    name: string;
    namespace: string;
    labels: Record<string, string>;
  };
  spec: {
    ttlSecondsAfterFinished: number;
    template: {
      spec: {
        restartPolicy: string;
        volumes: Array<{
          name: string;
          persistentVolumeClaim: { claimName: string };
        }>;
        containers: Array<{
          name: string;
          image: string;
          command: string[];
          args: string[];
          volumeMounts: Array<{ name: string; mountPath: string }>;
          env: Array<{ name: string; value: string }>;
          resources: {
            requests: { cpu: string; memory: string };
            limits: { cpu: string; memory: string };
          };
        }>;
      };
    };
  };
}

export function buildRalphJobSpec(runId: string, iterations: number): RalphJobSpec {
  return {
    apiVersion: 'batch/v1',
    kind: 'Job',
    metadata: {
      name: `ralph-run-${runId}`,
      namespace: NAMESPACE,
      labels: {
        'app.kubernetes.io/name': 'ralph',
        'sovereign-pm/run-id': runId,
      },
    },
    spec: {
      ttlSecondsAfterFinished: 3600,
      template: {
        spec: {
          restartPolicy: 'Never',
          volumes: [
            {
              name: 'prd-volume',
              persistentVolumeClaim: { claimName: PVC_NAME },
            },
          ],
          containers: [
            {
              name: 'ralph',
              image: SOVEREIGN_PM_IMAGE,
              command: ['/app/scripts/ralph/ralph.sh'],
              args: ['--tool', 'claude', String(iterations)],
              volumeMounts: [
                {
                  name: 'prd-volume',
                  mountPath: '/app/prd',
                },
              ],
              env: [
                { name: 'SOVEREIGN_RUN_ID', value: runId },
              ],
              resources: {
                requests: { cpu: '100m', memory: '128Mi' },
                limits: { cpu: '500m', memory: '512Mi' },
              },
            },
          ],
        },
      },
    },
  };
}

// POST /api/ralph/trigger
router.post('/trigger', async (req: Request, res: Response) => {
  const { storyId, iterations } = req.body as {
    storyId?: string;
    iterations?: number;
  };

  if (!storyId) {
    res.status(400).json({ error: 'storyId is required' });
    return;
  }

  const run = await AgentRun.create({
    storyId,
    status: 'running',
    logs: '',
    startedAt: new Date(),
    completedAt: null,
  });

  const jobSpec = buildRalphJobSpec(run.id, iterations ?? 10);

  res.status(202).json({
    runId: run.id,
    message: 'Ralph job queued',
    jobSpec,
  });
});

// GET /api/ralph/runs
router.get('/runs', async (_req: Request, res: Response) => {
  const runs = await AgentRun.findAll({ order: [['startedAt', 'DESC']] });
  res.json(runs);
});

export default router;
