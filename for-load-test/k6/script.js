import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://demo-load.demo.svc.cluster.local:8080';

export const options = {
  vus: 3,
  duration: '3m',
  thresholds: {
    http_req_duration: ['p(95)<8000'],
  },
};

export function setup() {
  const res = http.get(`${BASE}/health`);
  if (res.status !== 200) {
    throw new Error(`demo-load not ready at ${BASE}: HTTP ${res.status}`);
  }
}

export default function () {
  const r = Math.random();
  let path = '/work';
  if (r < 0.05) {
    path = '/error';
  } else if (r < 0.20) {
    path = '/slow';
  }

  const res = http.get(`${BASE}${path}`);
  check(res, {
    'status 200 or 500': (x) => x.status === 200 || x.status === 500,
  });
  sleep(0.2);
}
